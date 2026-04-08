@preconcurrency import AVFoundation
@preconcurrency import ApplicationServices
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
    private var analyzerFormat: AVAudioFormat?
    private var audioConverter: AVAudioConverter?
    private var converterInputSignature: String?
    private var usingModernSpeechPipeline = false
    private var modernSpeechPipeline: Any?

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

        if #available(macOS 26.0, *), usingModernSpeechPipeline {
            stopModernSpeechPipeline()
        }

        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        stream?.stopCapture { _ in }
        stream = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        analyzerFormat = nil
        audioConverter = nil
        converterInputSignature = nil
        usingModernSpeechPipeline = false
        modernSpeechPipeline = nil
        print("[SimulTrans] Stopped")
    }

    // MARK: - Start (runs detached)

    private func doStart(locale: Locale, source: AudioSource) async {
        resetAudioActivityTracking()
        analyzerFormat = nil
        audioConverter = nil
        converterInputSignature = nil
        usingModernSpeechPipeline = false

        if #available(macOS 26.0, *), SpeechTranscriber.isAvailable {
            do {
                try await startModernSpeechPipeline(locale: locale)
                usingModernSpeechPipeline = true
                print("[SimulTrans] SpeechTranscriber pipeline enabled")
            } catch {
                await MainActor.run {
                    self.onError?("新しい音声認識パイプラインの開始に失敗しました。旧方式にフォールバックします: \(error.localizedDescription)")
                }
                stopModernSpeechPipeline()
            }
        }

        if !usingModernSpeechPipeline {
            // 1. Setup speech recognizer
            let recognizer = SFSpeechRecognizer(locale: locale)
            guard let recognizer, recognizer.isAvailable else {
                await MainActor.run { self.onError?("音声認識を利用できません (\(locale.identifier))") }
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
                await MainActor.run { self.onError?("音声認識の権限が許可されていません") }
                return
            }
            print("[SimulTrans] Speech authorized")
            startRecognitionTask()
        }

        _isRunningAtomic.withLock { $0 = true }

        // 3. Start audio capture
        switch source {
        case .system:
            do {
                let hasScreenCaptureAccess = await MainActor.run { CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() }
                guard hasScreenCaptureAccess else {
                    _isRunningAtomic.withLock { $0 = false }
                    await MainActor.run {
                        self.onError?("画面収録の権限が必要です。システム設定で SimulTrans を許可したあと、もう一度開始してください。")
                    }
                    return
                }

                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let display = content.displays.first else {
                    await MainActor.run { self.onError?("ディスプレイが見つかりません") }
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
                _isRunningAtomic.withLock { $0 = false }
                await MainActor.run { self.onError?("音声キャプチャの開始に失敗しました: \(error.localizedDescription)") }
                return
            }

        case .microphone:
            do {
                try startMicrophoneCapture()
                print("[SimulTrans] Microphone capture started")
            } catch {
                _isRunningAtomic.withLock { $0 = false }
                await MainActor.run { self.onError?("マイク入力の開始に失敗しました: \(error.localizedDescription)") }
                return
            }
        }

        if usingModernSpeechPipeline {
            print("[SimulTrans] Recognition started with SpeechTranscriber (locale: \(locale.identifier))")
        } else {
            print("[SimulTrans] Recognition started with SFSpeechRecognizer (locale: \(locale.identifier))")
        }
    }

    // MARK: - Speech Recognition

    private func startRecognitionTask() {
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        request.taskHint = .dictation
        if speechRecognizer?.supportsOnDeviceRecognition == true {
            request.requiresOnDeviceRecognition = true
            print("[SimulTrans] On-device recognition enabled")
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
            if self.usingModernSpeechPipeline {
                guard let bufferCopy = self.copyPCMBuffer(buffer) else { return }
                self.audioQueue.async { [weak self] in
                    self?.submitBufferToModernSpeechPipeline(bufferCopy)
                }
            } else {
                let level = self.audioLevel(for: buffer)
                self.audioQueue.async { [weak self] in
                    self?.handleAudioActivity(level: level)
                }
                self.recognitionRequest?.append(buffer)
            }
        }

        try engine.start()
        self.audioEngine = engine
    }

    @available(macOS 26.0, *)
    private func startModernSpeechPipeline(locale: Locale) async throws {
        let selectedLocale = await SpeechTranscriber.supportedLocale(equivalentTo: locale) ?? locale
        let transcriber = SpeechTranscriber(locale: selectedLocale, preset: .timeIndexedProgressiveTranscription)
        guard let targetFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
            throw NSError(domain: "SimulTrans.Speech", code: 1, userInfo: [NSLocalizedDescriptionKey: "SpeechTranscriber と互換性のある音声フォーマットが見つかりませんでした"])
        }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: targetFormat)

        let pipeline = ModernSpeechPipeline(analyzer: analyzer, transcriber: transcriber)
        let inputStream = AsyncStream<AnalyzerInput> { continuation in
            pipeline.inputContinuation = continuation
        }

        analyzerFormat = targetFormat

        pipeline.resultsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }

                    self.lastSegmentText = result.isFinal ? "" : text
                    let segments = self.recognitionSegments(for: text, timeRange: result.range)
                    let update = RecognitionUpdate(text: text, isFinal: result.isFinal, segments: segments)
                    let callback = self.onResult
                    await MainActor.run { callback?(update) }
                }
            } catch is CancellationError {
                return
            } catch {
                guard self.isRunning else { return }
                let callback = self.onError
                await MainActor.run { callback?("SpeechTranscriber エラー: \(error.localizedDescription)") }
            }
        }

        pipeline.analyzerTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await analyzer.start(inputSequence: inputStream)
            } catch is CancellationError {
                return
            } catch {
                guard self.isRunning else { return }
                let callback = self.onError
                await MainActor.run { callback?("音声解析の開始に失敗しました: \(error.localizedDescription)") }
            }
        }

        modernSpeechPipeline = pipeline
    }

    @available(macOS 26.0, *)
    private func stopModernSpeechPipeline() {
        guard let pipeline = modernSpeechPipeline as? ModernSpeechPipeline else {
            modernSpeechPipeline = nil
            return
        }

        pipeline.inputContinuation?.finish()
        pipeline.resultsTask?.cancel()
        pipeline.analyzerTask?.cancel()

        Task {
            await pipeline.analyzer.cancelAndFinishNow()
        }

        modernSpeechPipeline = nil
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

    private func copyPCMBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameCapacity) else { return nil }
        copy.frameLength = buffer.frameLength

        let audioBufferList = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        let sourceBufferList = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)

        for (destination, source) in zip(audioBufferList, sourceBufferList) {
            guard let sourceData = source.mData, let destinationData = destination.mData else { continue }
            memcpy(destinationData, sourceData, Int(source.mDataByteSize))
        }

        return copy
    }

    private func submitBufferToModernSpeechPipeline(_ buffer: AVAudioPCMBuffer) {
        guard usingModernSpeechPipeline else { return }
        guard let convertedBuffer = convertedBufferForAnalyzer(from: buffer) else { return }
        if #available(macOS 26.0, *) {
            (modernSpeechPipeline as? ModernSpeechPipeline)?.inputContinuation?.yield(AnalyzerInput(buffer: convertedBuffer))
        }
    }

    private func convertedBufferForAnalyzer(from buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let analyzerFormat else { return nil }
        if buffer.format == analyzerFormat {
            return buffer
        }

        let inputSignature = formatSignature(for: buffer.format)
        if converterInputSignature != inputSignature {
            audioConverter = AVAudioConverter(from: buffer.format, to: analyzerFormat)
            converterInputSignature = inputSignature
        }

        guard let audioConverter else { return nil }
        let ratio = analyzerFormat.sampleRate / buffer.format.sampleRate
        let outputCapacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up) + 32)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: analyzerFormat, frameCapacity: outputCapacity) else { return nil }

        var conversionError: NSError?
        var didProvideInput = false
        let status = audioConverter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }

            didProvideInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        if status == .error {
            if let conversionError {
                print("[SimulTrans] Audio conversion failed: \(conversionError.localizedDescription)")
            }
            return nil
        }

        return outputBuffer.frameLength > 0 ? outputBuffer : nil
    }

    private func recognitionSegments(for text: String, timeRange: CMTimeRange) -> [RecognitionSegment] {
        guard !text.isEmpty else { return [] }
        let timestamp = numericSeconds(from: timeRange.start)
        let duration = numericSeconds(from: timeRange.duration)
        return [
            RecognitionSegment(
                text: text,
                rangeLocation: 0,
                rangeLength: text.utf16.count,
                timestamp: timestamp,
                duration: duration
            )
        ]
    }

    private func numericSeconds(from time: CMTime) -> TimeInterval {
        guard time.isNumeric else { return 0 }
        let seconds = CMTimeGetSeconds(time)
        return seconds.isFinite ? max(0, seconds) : 0
    }

    private func formatSignature(for format: AVAudioFormat) -> String {
        "\(format.commonFormat.rawValue)-\(format.sampleRate)-\(format.channelCount)-\(format.isInterleaved)"
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
        } else if let dest = pcmBuffer.int16ChannelData {
            memcpy(dest[0], dataPointer, min(dataLength, lengthAtOffset))
        }

        if usingModernSpeechPipeline {
            submitBufferToModernSpeechPipeline(pcmBuffer)
        } else {
            handleAudioActivity(level: audioLevel(for: pcmBuffer))
            recognitionRequest?.append(pcmBuffer)
        }
    }
}

@available(macOS 26.0, *)
private final class ModernSpeechPipeline {
    let analyzer: SpeechAnalyzer
    let transcriber: SpeechTranscriber
    var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    var resultsTask: Task<Void, Never>?
    var analyzerTask: Task<Void, Never>?

    init(analyzer: SpeechAnalyzer, transcriber: SpeechTranscriber) {
        self.analyzer = analyzer
        self.transcriber = transcriber
    }
}
