import AVFoundation
import Foundation
import os
import ScreenCaptureKit
import Speech

struct RecognitionUpdate: Sendable {
    let text: String
    let isFinal: Bool
    let segments: [RecognitionSegment]
}

struct RecognitionSegment: Sendable {
    let text: String
    let rangeLocation: Int
    let rangeLength: Int
    let timestamp: TimeInterval
    let duration: TimeInterval

    var range: NSRange {
        NSRange(location: rangeLocation, length: rangeLength)
    }

    var endTime: TimeInterval {
        timestamp + duration
    }
}

/// Captures system audio via ScreenCaptureKit and performs real-time speech recognition.
final class SystemAudioRecognizer: NSObject, @unchecked Sendable {
    private var stream: SCStream?
    private var audioEngine: AVAudioEngine?
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    private let _isRunningAtomic = OSAllocatedUnfairLock(initialState: false)
    var isRunning: Bool {
        _isRunningAtomic.withLock { $0 }
    }

    var onResult: (@Sendable @MainActor (RecognitionUpdate) -> Void)?
    var onError: (@Sendable @MainActor (String) -> Void)?
    var onUtteranceBoundary: (@Sendable @MainActor () -> Void)?

    /// Last text from current recognition segment (used to flush on restart)
    private var lastSegmentText: String = ""

    private let audioQueue = DispatchQueue(label: "com.simultrans.audio")
    private let recognitionRestartDelay: DispatchTimeInterval = .milliseconds(50)
    private let silenceBoundaryDuration: CFTimeInterval = 1.15
    private let speechLevelThreshold: Float = 0.010
    private var lastVoiceActivityTime: CFTimeInterval = CACurrentMediaTime()
    private var hasDetectedSpeech = false
    private var silenceBoundarySent = false

    enum AudioSource {
        case system
        case microphone
    }

    func start(locale: Locale, source: AudioSource = .system) {
        Task.detached { [weak self] in
            await self?.doStart(locale: locale, source: source)
        }
    }

    func stop() {
        _isRunningAtomic.withLock { $0 = false }
        resetAudioActivityTracking()

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        stream?.stopCapture { _ in }
        stream = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        print("[SimulTrans] Stopped")
    }

    // MARK: - Start (runs detached)

    private func doStart(locale: Locale, source: AudioSource) async {
        resetAudioActivityTracking()

        // 1. Setup speech recognizer
        let recognizer = SFSpeechRecognizer(locale: locale)
        guard let recognizer, recognizer.isAvailable else {
            await MainActor.run { self.onError?("语音识别不可用 (\(locale.identifier))") }
            return
        }
        speechRecognizer = recognizer

        // 2. Request authorization
        let status = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        guard status == .authorized else {
            await MainActor.run { self.onError?("语音识别未授权") }
            return
        }
        print("[SimulTrans] Speech authorized")

        // 3. Start audio capture
        switch source {
        case .system:
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let display = content.displays.first else {
                    await MainActor.run { self.onError?("未找到显示器") }
                    return
                }
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.capturesAudio = true
                config.excludesCurrentProcessAudio = true
                config.channelCount = 1
                config.sampleRate = 48000
                config.width = 2
                config.height = 2

                let stream = SCStream(filter: filter, configuration: config, delegate: nil)
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
                try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: audioQueue)
                try await stream.startCapture()
                self.stream = stream
                print("[SimulTrans] System audio capture started")
            } catch {
                await MainActor.run { self.onError?("音频捕获失败: \(error.localizedDescription)") }
                return
            }

        case .microphone:
            do {
                try startMicrophoneCapture()
                print("[SimulTrans] Microphone capture started")
            } catch {
                await MainActor.run { self.onError?("麦克风启动失败: \(error.localizedDescription)") }
                return
            }
        }

        // 4. Start recognition
        startRecognitionTask()

        _isRunningAtomic.withLock { $0 = true }
        print("[SimulTrans] Recognition started (locale: \(locale.identifier))")
    }

    // MARK: - Speech Recognition

    private func startRecognitionTask() {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        if speechRecognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
            print("[SimulTrans] On-device recognition")
        }

        recognitionRequest = request

        lastSegmentText = ""

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }

            if let result {
                let text = result.bestTranscription.formattedString
                self.lastSegmentText = text
                let isFinal = result.isFinal
                let update = RecognitionUpdate(
                    text: text,
                    isFinal: isFinal,
                    segments: result.bestTranscription.segments.map {
                        RecognitionSegment(
                            text: $0.substring,
                            rangeLocation: $0.substringRange.location,
                            rangeLength: $0.substringRange.length,
                            timestamp: $0.timestamp,
                            duration: $0.duration
                        )
                    }
                )
                let callback = self.onResult
                DispatchQueue.main.async { callback?(update) }
                if isFinal {
                    self.lastSegmentText = ""
                    self.restartRecognition()
                }
            }

            if let nsError = error as? NSError {
                // Don't double-flush if we already handled isFinal
                if result?.isFinal != true {
                    print("[SimulTrans] Error \(nsError.code), flushing segment")
                    self.flushAndRestart()
                }
            }
        }
    }

    private func startMicrophoneCapture() throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self, self.isRunning else { return }
            // Apply gain for quiet environments
            if let channelData = buffer.floatChannelData {
                let gain: Float = 2.0
                let count = Int(buffer.frameLength)
                for ch in 0..<Int(buffer.format.channelCount) {
                    for i in 0..<count {
                        channelData[ch][i] = max(-1.0, min(1.0, channelData[ch][i] * gain))
                    }
                }
            }
            let level = self.audioLevel(for: buffer)
            self.audioQueue.async { [weak self] in
                self?.handleAudioActivity(level: level)
            }
            self.recognitionRequest?.append(buffer)
        }

        try engine.start()
        self.audioEngine = engine
    }

    /// Flush unsaved text as final result, then restart
    private func flushAndRestart() {
        guard isRunning else { return }

        // Send last text as final result so it gets saved to history
        if !lastSegmentText.isEmpty {
            let text = lastSegmentText
            let update = RecognitionUpdate(
                text: text,
                isFinal: true,
                segments: []
            )
            let callback = self.onResult
            lastSegmentText = ""
            DispatchQueue.main.async { callback?(update) }
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        scheduleRecognitionRestart()
    }

    private func restartRecognition() {
        guard isRunning else { return }
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil

        scheduleRecognitionRestart()
    }

    private func scheduleRecognitionRestart() {
        DispatchQueue.global().asyncAfter(deadline: .now() + recognitionRestartDelay) { [weak self] in
            guard let self, self.isRunning else { return }
            self.startRecognitionTask()
            print("[SimulTrans] Recognition restarted")
        }
    }

    private func resetAudioActivityTracking() {
        lastVoiceActivityTime = CACurrentMediaTime()
        hasDetectedSpeech = false
        silenceBoundarySent = false
    }

    private func handleAudioActivity(level: Float) {
        let now = CACurrentMediaTime()

        if level >= speechLevelThreshold {
            lastVoiceActivityTime = now
            hasDetectedSpeech = true
            silenceBoundarySent = false
            return
        }

        guard hasDetectedSpeech, !silenceBoundarySent else { return }
        guard now - lastVoiceActivityTime >= silenceBoundaryDuration else { return }

        silenceBoundarySent = true
        let callback = onUtteranceBoundary
        DispatchQueue.main.async { callback?() }
    }

    private func audioLevel(for buffer: AVAudioPCMBuffer) -> Float {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }

        if let channelData = buffer.floatChannelData {
            let samples = channelData[0]
            var sumSquares: Float = 0
            for i in 0..<frameCount {
                let sample = samples[i]
                sumSquares += sample * sample
            }
            return sqrt(sumSquares / Float(frameCount))
        }

        if let channelData = buffer.int16ChannelData {
            let samples = channelData[0]
            var sumSquares: Float = 0
            for i in 0..<frameCount {
                let sample = Float(samples[i]) / Float(Int16.max)
                sumSquares += sample * sample
            }
            return sqrt(sumSquares / Float(frameCount))
        }

        return 0
    }
}

// MARK: - SCStreamOutput

extension SystemAudioRecognizer: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        guard let formatDesc = sampleBuffer.formatDescription,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) else { return }

        guard let sourceFormat = AVAudioFormat(streamDescription: asbd) else { return }
        let frameCount = AVAudioFrameCount(sampleBuffer.numSamples)
        guard frameCount > 0 else { return }

        guard let blockBuffer = sampleBuffer.dataBuffer else { return }
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount) else { return }
        pcmBuffer.frameLength = frameCount

        let bytesPerFrame = Int(sourceFormat.streamDescription.pointee.mBytesPerFrame)
        let dataLength = Int(frameCount) * bytesPerFrame
        guard dataLength > 0 else { return }

        var lengthAtOffset: Int = 0
        var dataPointer: UnsafeMutablePointer<CChar>?
        let status = CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: &lengthAtOffset, totalLengthOut: nil, dataPointerOut: &dataPointer)
        guard status == noErr, let dataPointer else { return }

        if let dest = pcmBuffer.floatChannelData {
            memcpy(dest[0], dataPointer, min(dataLength, lengthAtOffset))
            // Amplify audio for better recognition of quiet sources
            let gain: Float = 3.0
            let count = Int(frameCount)
            for i in 0..<count {
                dest[0][i] = max(-1.0, min(1.0, dest[0][i] * gain))
            }
        } else if let dest = pcmBuffer.int16ChannelData {
            memcpy(dest[0], dataPointer, min(dataLength, lengthAtOffset))
        }

        handleAudioActivity(level: audioLevel(for: pcmBuffer))
        recognitionRequest?.append(pcmBuffer)
    }
}
