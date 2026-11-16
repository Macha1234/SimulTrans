@preconcurrency import AVFoundation
import Foundation
import os

final class LocalSpeechRecognizer: @unchecked Sendable {
    private struct AudioChunk {
        let buffer: AVAudioPCMBuffer
        let duration: TimeInterval
        let isForcedOverlap: Bool
    }

    private enum FlushReason {
        case preview
        case silence
        case forcedLimit
        case stop
    }

    fileprivate enum LocalASRError: LocalizedError {
        case unsupportedEngine
        case missingExecutable(String)
        case missingModel(String)
        case audioWriteFailed
        case serverUnavailable(String)
        case emptyResponse
        case httpError(Int, String)
        case timedOut(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedEngine:
                return "The selected recognition engine is not a local ASR engine."
            case .missingExecutable(let message),
                 .missingModel(let message),
                 .serverUnavailable(let message),
                 .timedOut(let message):
                return message
            case .audioWriteFailed:
                return "Could not prepare audio for the local recognizer."
            case .emptyResponse:
                return "The local recognizer returned an empty response."
            case .httpError(let code, let body):
                return "The local recognizer returned HTTP \(code): \(body)"
            }
        }
    }

    var onResult: (@Sendable @MainActor (RecognitionUpdate) -> Void)?
    var onError: (@Sendable @MainActor (String) -> Void)?

    private let engine: RecognitionEngine
    private let locale: Locale
    private let workerQueue = DispatchQueue(label: "com.simultrans.local-asr.audio")
    private let transcriptionQueue = DispatchQueue(label: "com.simultrans.local-asr.transcription")
    private let client = LocalASRClient()
    private let transcribeAudio: (@Sendable (URL) throws -> String)?
    private let latestPreview = OSAllocatedUnfairLock<UUID?>(initialState: nil)

    private var preRollChunks: [AudioChunk] = []
    private var activeChunks: [AudioChunk] = []
    private var preRollDuration: TimeInterval = 0
    private var activeDuration: TimeInterval = 0
    private var isSpeechActive = false
    private var trailingSilenceDuration: TimeInterval = 0
    private var isStopped = false
    private var activeStartsWithForcedOverlap = false
    private var utterance = UtteranceAccumulator()
    private var hasReportedConfigurationError = false
    private var newVoiceDuration: TimeInterval = 0
    private var durationAtLastPreview: TimeInterval = 0
    private var windowPreviousTranscript = ""

    private let preRollDurationLimit: TimeInterval = 0.45
    private let silenceBoundaryDuration: TimeInterval = 1.0
    private let maximumUtteranceDuration: TimeInterval = 24.0
    private let forcedOverlapDuration: TimeInterval = 0.35
    private let speechLevelThreshold: Float = 0.010

    init(engine: RecognitionEngine, locale: Locale,
         transcribeAudio: (@Sendable (URL) throws -> String)? = nil) {
        self.transcribeAudio = transcribeAudio
        self.engine = engine
        self.locale = locale
    }

    static func stopLocalASRServers() {
        LocalASRServerManager.shared.stopAllServers()
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        workerQueue.async { [weak self] in
            self?.consume(buffer)
        }
    }

    func stop() {
        workerQueue.async { [weak self] in
            guard let self else { return }
            self.isStopped = true
            self.flushActiveChunks(reason: .stop)
        }
    }

    private func consume(_ buffer: AVAudioPCMBuffer) {
        guard !isStopped else { return }
        let duration = bufferDuration(buffer)
        guard duration > 0 else { return }

        let chunk = AudioChunk(buffer: buffer, duration: duration, isForcedOverlap: false)
        let level = audioLevel(for: buffer)

        if level >= speechLevelThreshold {
            if !isSpeechActive {
                activeChunks = preRollChunks
                activeDuration = preRollDuration
                activeStartsWithForcedOverlap = preRollChunks.contains(where: \.isForcedOverlap)
                preRollChunks.removeAll()
                preRollDuration = 0
                isSpeechActive = true
            }

            appendActiveChunk(chunk)
            newVoiceDuration += duration
            trailingSilenceDuration = 0

            if activeDuration >= maximumUtteranceDuration {
                flushActiveChunks(reason: .forcedLimit)
            } else if activeDuration - durationAtLastPreview >= 3.0 {
                durationAtLastPreview = activeDuration
                flushActiveChunks(reason: .preview)
            }
            return
        }

        if isSpeechActive {
            appendActiveChunk(chunk)
            trailingSilenceDuration += duration
            if trailingSilenceDuration >= silenceBoundaryDuration {
                flushActiveChunks(reason: .silence)
            }
        } else {
            appendPreRollChunk(chunk)
        }
    }

    private func appendPreRollChunk(_ chunk: AudioChunk) {
        preRollChunks.append(chunk)
        preRollDuration += chunk.duration

        while preRollDuration > preRollDurationLimit, !preRollChunks.isEmpty {
            preRollDuration -= preRollChunks.removeFirst().duration
        }
    }

    private func appendActiveChunk(_ chunk: AudioChunk) {
        activeChunks.append(chunk)
        activeDuration += chunk.duration
    }

    private func flushActiveChunks(reason: FlushReason) {
        let chunks = activeChunks
        let duration = activeDuration
        let startsWithForcedOverlap = activeStartsWithForcedOverlap
        let hasNewVoice = newVoiceDuration > 0
        let submittedAt = Date()
        let previewID = UUID()
        latestPreview.withLock { $0 = reason == .preview ? previewID : nil }

        if reason != .preview {
            activeChunks.removeAll()
            activeDuration = 0
            activeStartsWithForcedOverlap = false
            isSpeechActive = false
            trailingSilenceDuration = 0
            newVoiceDuration = 0
            durationAtLastPreview = 0

            if reason == .forcedLimit {
                let overlap = trailingChunks(from: chunks, durationLimit: forcedOverlapDuration)
                    .map { AudioChunk(buffer: $0.buffer, duration: $0.duration, isForcedOverlap: true) }
                activeChunks = overlap
                activeDuration = overlap.reduce(0) { $0 + $1.duration }
                activeStartsWithForcedOverlap = true
                isSpeechActive = true
            }
        }

        guard !chunks.isEmpty else { return }
        if reason == .preview && !hasNewVoice { return }

        transcriptionQueue.async { [self] in
            // Coalesce obsolete previews when inference is slower than audio.
            if reason == .preview, latestPreview.withLock({ $0 }) != previewID { return }
            let queueDuration = Date().timeIntervalSince(submittedAt)
            do {
                let processingStartedAt = Date()
                var rawText = ""
                if hasNewVoice {
                    // Do not ask a language model to decode overlap + silence
                    // without any new speech. Keep a small acoustic tail only.
                    var inputChunks = chunks
                    var tailDuration: TimeInterval = 0
                    let silenceDuration = trailingSilence(in: chunks)
                    while let last = inputChunks.last,
                          audioLevel(for: last.buffer) < speechLevelThreshold,
                          tailDuration + last.duration < max(0, silenceDuration - 0.2) {
                        tailDuration += inputChunks.removeLast().duration
                    }
                    let audioURL = try writeTemporaryWAV(chunks: inputChunks)
                    defer { try? FileManager.default.removeItem(at: audioURL) }
                    if let transcribeAudio {
                        rawText = try transcribeAudio(audioURL)
                    } else {
                        rawText = try client.transcribe(audioURL: audioURL, engine: engine, locale: locale)
                    }
                    rawText = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                let processingDuration = Date().timeIntervalSince(processingStartedAt)
                let text = startsWithForcedOverlap
                    ? Self.removingForcedOverlap(previous: windowPreviousTranscript, current: rawText)
                    : rawText
                // Every window close (silence, stop, or the 24 s limit) finalizes a row,
                // so continuous speech never grows into one unbounded, untranslated block.
                let result = utterance.update(text, endsUtterance: reason == .silence
                                              || reason == .stop || reason == .forcedLimit)
                // The next window starts with a short audio overlap after a forced cut;
                // keep this transcript so that overlap can be removed from the next row.
                // Previews must not touch it, or later flushes lose the overlap reference.
                if reason == .forcedLimit {
                    windowPreviousTranscript = rawText
                } else if result.isFinal {
                    windowPreviousTranscript = ""
                }
                guard !result.text.isEmpty else { return }
                let update = RecognitionUpdate(text: result.text, isFinal: result.isFinal,
                                               segments: [], timing: RecognitionTiming(utteranceDuration: duration,
                                                   queueDuration: queueDuration, processingDuration: processingDuration))
                let callback = onResult
                DispatchQueue.main.async { callback?(update) }
            } catch {
                reportErrorOnce(error.localizedDescription)
            }
        }
    }

    private func trailingSilence(in chunks: [AudioChunk]) -> TimeInterval {
        var duration: TimeInterval = 0
        for chunk in chunks.reversed() {
            guard audioLevel(for: chunk.buffer) < speechLevelThreshold else { break }
            duration += chunk.duration
        }
        return duration
    }

    private func trailingChunks(from chunks: [AudioChunk],
                                durationLimit: TimeInterval) -> [AudioChunk] {
        var selected: [AudioChunk] = []
        var selectedDuration: TimeInterval = 0
        for chunk in chunks.reversed() where selectedDuration < durationLimit {
            selected.append(chunk)
            selectedDuration += chunk.duration
        }
        return selected.reversed()
    }

    private static func removingForcedOverlap(previous: String, current: String) -> String {
        guard !previous.isEmpty, !current.isEmpty else { return current }
        let previousCharacters = Array(previous)
        let currentCharacters = Array(current)
        let maximumOverlap = min(previousCharacters.count, currentCharacters.count)

        for count in stride(from: maximumOverlap, through: 1, by: -1) {
            let previousSuffix = String(previousCharacters[(previousCharacters.count - count)...])
            let currentPrefix = String(currentCharacters[..<count])
            guard previousSuffix == currentPrefix else { continue }

            let containsCJK = currentPrefix.unicodeScalars.contains { scalar in
                switch scalar.value {
                case 0x3040...0x30FF, 0x3400...0x9FFF, 0xAC00...0xD7AF:
                    return true
                default:
                    return false
                }
            }
            let minimumOverlap = containsCJK ? 2 : 4
            guard count >= minimumOverlap else { continue }
            return String(currentCharacters.dropFirst(count))
        }
        return current
    }

    private func reportErrorOnce(_ message: String) {
        guard !hasReportedConfigurationError else { return }
        hasReportedConfigurationError = true
        let callback = onError
        DispatchQueue.main.async { callback?(message) }
    }

    private func writeTemporaryWAV(chunks: [AudioChunk]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimulTransLocalASR", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                               sampleRate: 16_000,
                                               channels: 1,
                                               interleaved: false) else {
            throw LocalASRError.audioWriteFailed
        }

        var pcmData = Data()

        for chunk in chunks {
            guard let converted = convertedBuffer(chunk.buffer, to: targetFormat),
                  converted.frameLength > 0 else { continue }
            appendPCM16Samples(from: converted, to: &pcmData)
        }

        guard !pcmData.isEmpty else {
            throw LocalASRError.audioWriteFailed
        }

        let wavData = Self.wavData(pcmData: pcmData,
                                   sampleRate: 16_000,
                                   channels: 1,
                                   bitsPerSample: 16)
        try wavData.write(to: url, options: .atomic)
        return url
    }

    private func appendPCM16Samples(from buffer: AVAudioPCMBuffer, to data: inout Data) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        let samples = channelData[0]
        data.reserveCapacity(data.count + frameCount * MemoryLayout<Int16>.size)

        for frame in 0..<frameCount {
            let clamped = min(max(samples[frame], -1.0), 1.0)
            var sample = Int16(clamped * Float(Int16.max)).littleEndian
            Swift.withUnsafeBytes(of: &sample) { bytes in
                data.append(contentsOf: bytes)
            }
        }
    }

    private static func wavData(pcmData: Data,
                                sampleRate: UInt32,
                                channels: UInt16,
                                bitsPerSample: UInt16) -> Data {
        let byteRate = sampleRate * UInt32(channels) * UInt32(bitsPerSample) / 8
        let blockAlign = channels * bitsPerSample / 8
        let dataSize = UInt32(pcmData.count)

        var data = Data()
        data.reserveCapacity(44 + pcmData.count)
        data.appendString("RIFF")
        data.appendLittleEndian(UInt32(36) + dataSize)
        data.appendString("WAVE")
        data.appendString("fmt ")
        data.appendLittleEndian(UInt32(16))
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(channels)
        data.appendLittleEndian(sampleRate)
        data.appendLittleEndian(byteRate)
        data.appendLittleEndian(blockAlign)
        data.appendLittleEndian(bitsPerSample)
        data.appendString("data")
        data.appendLittleEndian(dataSize)
        data.append(pcmData)
        return data
    }

    private func convertedBuffer(_ buffer: AVAudioPCMBuffer, to targetFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == targetFormat {
            return buffer
        }

        guard let converter = AVAudioConverter(from: buffer.format, to: targetFormat) else {
            return nil
        }

        let ratio = targetFormat.sampleRate / max(buffer.format.sampleRate, 1)
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up) + 64)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else {
            return nil
        }

        var didProvideInput = false
        var conversionError: NSError?
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
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
                print("[SimulTrans] Local ASR audio conversion failed: \(conversionError.localizedDescription)")
            }
            return nil
        }

        return outputBuffer
    }

    private func bufferDuration(_ buffer: AVAudioPCMBuffer) -> TimeInterval {
        Double(buffer.frameLength) / max(buffer.format.sampleRate, 1)
    }

    private func audioLevel(for buffer: AVAudioPCMBuffer) -> Float {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0 }

        if let channelData = buffer.floatChannelData {
            let channels = Int(buffer.format.channelCount)
            var sumSquares: Float = 0
            var sampleCount = 0

            for channel in 0..<max(channels, 1) {
                let samples = channelData[channel]
                for frame in 0..<frameCount {
                    let sample = samples[frame]
                    sumSquares += sample * sample
                    sampleCount += 1
                }
            }

            return sampleCount > 0 ? sqrt(sumSquares / Float(sampleCount)) : 0
        }

        if let channelData = buffer.int16ChannelData {
            let channels = Int(buffer.format.channelCount)
            var sumSquares: Float = 0
            var sampleCount = 0

            for channel in 0..<max(channels, 1) {
                let samples = channelData[channel]
                for frame in 0..<frameCount {
                    let sample = Float(samples[frame]) / Float(Int16.max)
                    sumSquares += sample * sample
                    sampleCount += 1
                }
            }

            return sampleCount > 0 ? sqrt(sumSquares / Float(sampleCount)) : 0
        }

        return 0
    }
}

private final class LocalASRClient {
    private let serverManager = LocalASRServerManager.shared
    private var serverConfirmed = false

    func transcribe(audioURL: URL, engine: RecognitionEngine, locale: Locale) throws -> String {
        let config = try LocalASRServerConfig(engine: engine)
        if !serverConfirmed {
            try serverManager.ensureServer(config)
            serverConfirmed = true
        }

        var lastError: Error?
        for attempt in 0..<2 {
            do {
                let result = try postTranscription(audioURL: audioURL,
                                                   config: config,
                                                   locale: locale,
                                                   timeout: attempt == 0 ? 12 : 30)
                serverConfirmed = true
                return result
            } catch {
                lastError = error
                if !shouldRetry(error) { break }
                serverConfirmed = false
                if attempt == 0 {
                    try? serverManager.ensureServer(config)
                    Thread.sleep(forTimeInterval: 0.2)
                }
            }
        }

        throw lastError ?? LocalSpeechRecognizer.LocalASRError.emptyResponse
    }

    private func shouldRetry(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return true
        }

        if case LocalSpeechRecognizer.LocalASRError.httpError(let code, _) = error {
            return code >= 500 || code == 404
        }

        if case LocalSpeechRecognizer.LocalASRError.timedOut = error {
            return true
        }

        return false
    }

    private func postTranscription(audioURL: URL,
                                   config: LocalASRServerConfig,
                                   locale: Locale,
                                   timeout: TimeInterval) throws -> String {
        var request = URLRequest(url: config.endpointURL)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout

        if let bearerToken = config.bearerToken {
            request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }

        let boundary = "SimulTransBoundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendMultipartField(name: "model", value: config.modelParameter, boundary: boundary)
        body.appendMultipartField(name: "response_format", value: "json", boundary: boundary)
        body.appendMultipartField(name: "temperature", value: "0.0", boundary: boundary)
        body.appendMultipartField(name: "language", value: config.languageParameter(for: locale), boundary: boundary)
        try body.appendMultipartFile(name: "file",
                                     filename: audioURL.lastPathComponent,
                                     mimeType: "audio/wav",
                                     fileURL: audioURL,
                                     boundary: boundary)
        body.appendString("--\(boundary)--\r\n")
        request.httpBody = body

        let (data, response) = try Self.sendSynchronously(request, timeout: timeout + 5)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw LocalSpeechRecognizer.LocalASRError.httpError(http.statusCode, body)
        }

        if let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let text = parsed["text"] as? String {
                return cleanTranscript(text)
            }
            if let text = parsed["transcription"] as? String {
                return cleanTranscript(text)
            }
        }

        guard let rawText = String(data: data, encoding: .utf8) else {
            throw LocalSpeechRecognizer.LocalASRError.emptyResponse
        }

        return cleanTranscript(rawText)
    }

    private func cleanTranscript(_ text: String) -> String {
        text
            .components(separatedBy: .newlines)
            .map { line in
                line.replacingOccurrences(of: #"^\[[0-9:.,\s\->]+\]\s*"#,
                                          with: "",
                                          options: .regularExpression)
            }
            .joined(separator: " ")
            .replacingOccurrences(of: #"^\s*text\s*:\s*"#,
                                  with: "",
                                  options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sendSynchronously(_ request: URLRequest,
                                          timeout: TimeInterval) throws -> (Data, URLResponse) {
        let semaphore = DispatchSemaphore(value: 0)
        let resultBox = LockedValue<Result<(Data, URLResponse), Error>?>(nil)

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                resultBox.set(.failure(error))
            } else if let data, let response {
                resultBox.set(.success((data, response)))
            } else {
                resultBox.set(.failure(LocalSpeechRecognizer.LocalASRError.emptyResponse))
            }
            semaphore.signal()
        }
        task.resume()

        if semaphore.wait(timeout: .now() + timeout) == .timedOut {
            task.cancel()
            throw LocalSpeechRecognizer.LocalASRError.timedOut("Timed out waiting for the local recognizer.")
        }

        if let result = resultBox.get() {
            return try result.get()
        }

        throw LocalSpeechRecognizer.LocalASRError.emptyResponse
    }
}

private struct LocalASRServerConfig {
    let engine: RecognitionEngine
    let endpointURL: URL
    let healthURL: URL
    let healthMarker: String?
    let executablePath: String
    let arguments: [String]
    let modelParameter: String
    let bearerToken: String?

    init(engine: RecognitionEngine) throws {
        self.engine = engine

        switch engine {
        case .appleSpeech:
            throw LocalSpeechRecognizer.LocalASRError.unsupportedEngine

        case .whisperLargeV3Turbo:
            let modelPath = try Self.whisperModelPath()
            executablePath = try Self.executablePath(
                environmentKey: "SIMULTRANS_WHISPER_SERVER",
                candidates: [
                    "/opt/homebrew/bin/whisper-server",
                    "/usr/local/bin/whisper-server",
                    "\(Self.homeDirectory)/whisper.cpp/build/bin/whisper-server",
                    "\(Self.homeDirectory)/vscode/whisper.cpp/build/bin/whisper-server"
                ],
                setupName: "whisper-server"
            )
            endpointURL = URL(string: "http://127.0.0.1:2022/v1/audio/transcriptions")!
            healthURL = URL(string: "http://127.0.0.1:2022/")!
            healthMarker = nil
            arguments = [
                "--host", "127.0.0.1",
                "--port", "2022",
                "--model", modelPath,
                "--inference-path", "/v1/audio/transcriptions",
                "--threads", "8",
                "--processors", "1"
            ]
            modelParameter = "whisper-large-v3-turbo"
            bearerToken = nil

        case .qwen3ASR1_7B:
            let sidecarPath = try Self.executablePath(
                environmentKey: "SIMULTRANS_QWEN3_ASR_SIDECAR",
                candidates: [
                    "\(Self.homeDirectory)/vscode/SimulTrans-github/scripts/qwen3_asr_server.py",
                    "\(Self.homeDirectory)/vscode/SimulTrans/scripts/qwen3_asr_server.py"
                ],
                setupName: "SimulTrans Qwen3 ASR sidecar"
            )
            executablePath = try Self.executablePath(
                environmentKey: "SIMULTRANS_QWEN3_ASR_PYTHON",
                candidates: [
                    "/Library/Frameworks/Python.framework/Versions/3.14/bin/python3",
                    "/Library/Frameworks/Python.framework/Versions/3.13/bin/python3",
                    "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3",
                    "/Library/Frameworks/Python.framework/Versions/3.11/bin/python3",
                    "/Library/Frameworks/Python.framework/Versions/3.10/bin/python3",
                    "/opt/homebrew/bin/python3",
                    "/usr/local/bin/python3",
                    "/usr/bin/python3"
                ],
                setupName: "Python with mlx-qwen3-asr"
            )
            endpointURL = URL(string: "http://127.0.0.1:8765/v1/audio/transcriptions")!
            healthURL = URL(string: "http://127.0.0.1:8765/health")!
            healthMarker = "simultrans-qwen-sidecar"
            arguments = [
                sidecarPath,
                "--host", "127.0.0.1",
                "--port", "8765",
                "--model", "Qwen/Qwen3-ASR-1.7B",
                "--dtype", "float16",
                "--parent-pid", "\(ProcessInfo.processInfo.processIdentifier)",
                "--api-key", "simultrans-local"
            ]
            modelParameter = "Qwen/Qwen3-ASR-1.7B"
            bearerToken = "simultrans-local"
        }
    }

    func languageParameter(for locale: Locale) -> String {
        switch engine {
        case .appleSpeech:
            return locale.identifier
        case .whisperLargeV3Turbo:
            return Self.whisperLanguageCode(for: locale)
        case .qwen3ASR1_7B:
            return Self.qwenLanguageName(for: locale)
        }
    }

    private static var homeDirectory: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }

    private static func executablePath(environmentKey: String,
                                       candidates: [String],
                                       setupName: String) throws -> String {
        let fileManager = FileManager.default
        if let override = ProcessInfo.processInfo.environment[environmentKey],
           fileManager.isExecutableFile(atPath: override) {
            return override
        }

        if let found = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return found
        }

        throw LocalSpeechRecognizer.LocalASRError.missingExecutable(
            "Could not find \(setupName). Install it first, or set \(environmentKey) before launching SimulTrans."
        )
    }

    private static func whisperModelPath() throws -> String {
        let fileManager = FileManager.default
        if let override = ProcessInfo.processInfo.environment["SIMULTRANS_WHISPER_MODEL"],
           fileManager.fileExists(atPath: override) {
            return override
        }

        let appSupport = fileManager.urls(for: .applicationSupportDirectory,
                                          in: .userDomainMask)
            .first?
            .appendingPathComponent("SimulTrans/Models/whisper", isDirectory: true)

        let candidates = [
            appSupport?.appendingPathComponent("ggml-large-v3-turbo-q8_0.bin").path,
            appSupport?.appendingPathComponent("ggml-large-v3-turbo.bin").path,
            "\(homeDirectory)/whisper.cpp/models/ggml-large-v3-turbo-q8_0.bin",
            "\(homeDirectory)/whisper.cpp/models/ggml-large-v3-turbo.bin",
            "\(homeDirectory)/vscode/whisper.cpp/models/ggml-large-v3-turbo-q8_0.bin",
            "\(homeDirectory)/vscode/whisper.cpp/models/ggml-large-v3-turbo.bin"
        ].compactMap { $0 }

        if let found = candidates.first(where: { fileManager.fileExists(atPath: $0) }) {
            return found
        }

        let expectedPath = appSupport?
            .appendingPathComponent("ggml-large-v3-turbo-q8_0.bin")
            .path ?? "~/Library/Application Support/SimulTrans/Models/whisper/ggml-large-v3-turbo-q8_0.bin"

        throw LocalSpeechRecognizer.LocalASRError.missingModel(
            "Could not find the Whisper large-v3-turbo model. Put it at \(expectedPath), or set SIMULTRANS_WHISPER_MODEL before launching SimulTrans."
        )
    }

    private static func whisperLanguageCode(for locale: Locale) -> String {
        let identifier = locale.identifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()

        if identifier.hasPrefix("zh") { return "zh" }
        if identifier.hasPrefix("ja") { return "ja" }
        if identifier.hasPrefix("ko") { return "ko" }
        if identifier.hasPrefix("en") { return "en" }
        if identifier.hasPrefix("pt") { return "pt" }
        if identifier.count >= 2 {
            return String(identifier.prefix(2))
        }
        return "auto"
    }

    private static func qwenLanguageName(for locale: Locale) -> String {
        let identifier = locale.identifier
            .replacingOccurrences(of: "_", with: "-")
            .lowercased()

        if identifier.hasPrefix("ja") { return "Japanese" }
        if identifier.hasPrefix("zh") { return "Chinese" }
        if identifier.hasPrefix("ko") { return "Korean" }
        if identifier.hasPrefix("en") { return "English" }
        if identifier.hasPrefix("es") { return "Spanish" }
        if identifier.hasPrefix("fr") { return "French" }
        if identifier.hasPrefix("de") { return "German" }
        if identifier.hasPrefix("it") { return "Italian" }
        if identifier.hasPrefix("pt") { return "Portuguese" }
        if identifier.hasPrefix("ru") { return "Russian" }
        if identifier.hasPrefix("th") { return "Thai" }
        if identifier.hasPrefix("vi") { return "Vietnamese" }
        return Locale(identifier: "en").localizedString(forIdentifier: locale.identifier) ?? "English"
    }
}

private final class LocalASRServerManager: @unchecked Sendable {
    static let shared = LocalASRServerManager()

    private let lock = NSLock()
    private var processes: [RecognitionEngine: Process] = [:]

    private init() {}

    func ensureServer(_ config: LocalASRServerConfig) throws {
        if isEndpointReachable(config) {
            return
        }

        lock.lock()
        defer { lock.unlock() }

        if let process = processes[config.engine], process.isRunning {
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: config.executablePath)
        process.arguments = config.arguments
        process.environment = ProcessInfo.processInfo.environment.merging(config.processEnvironment) { _, replacement in
            replacement
        }

        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimulTrans-\(config.engine.rawValue)-server.log")
        try? FileManager.default.removeItem(at: logURL)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        if let logHandle = try? FileHandle(forWritingTo: logURL) {
            process.standardOutput = logHandle
            process.standardError = logHandle
        }

        do {
            try process.run()
            processes[config.engine] = process
            Thread.sleep(forTimeInterval: 0.8)
            if !process.isRunning {
                processes[config.engine] = nil
                let logText = (try? String(contentsOf: logURL, encoding: .utf8))
                    .map { String($0.suffix(1200)) }?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let detail = logText?.isEmpty == false ? "\n\(logText!)" : ""
                throw LocalSpeechRecognizer.LocalASRError.serverUnavailable(
                    "\(config.engine.displayName) server exited immediately.\(detail)"
                )
            }
            print("[SimulTrans] Started \(config.engine.displayName) server: \(config.executablePath)")
        } catch {
            if let localError = error as? LocalSpeechRecognizer.LocalASRError {
                throw localError
            }
            throw LocalSpeechRecognizer.LocalASRError.serverUnavailable(
                "Could not start \(config.engine.displayName): \(error.localizedDescription)"
            )
        }
    }

    func stopAllServers() {
        lock.lock()
        let activeProcesses = processes.values
        processes.removeAll()
        lock.unlock()

        for process in activeProcesses where process.isRunning {
            process.terminate()
        }
    }

    private func isEndpointReachable(_ config: LocalASRServerConfig) -> Bool {
        var request = URLRequest(url: config.healthURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 0.6

        let semaphore = DispatchSemaphore(value: 0)
        let reached = LockedValue(false)

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil, response != nil else {
                reached.set(false)
                semaphore.signal()
                return
            }

            if let marker = config.healthMarker {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
                reached.set(body.contains(marker))
            } else {
                reached.set(true)
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 0.8)
        task.cancel()
        return reached.get()
    }
}

private extension LocalASRServerConfig {
    var processEnvironment: [String: String] {
        var environment = [
            "PATH": "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Python/3.14/bin:\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Python/3.13/bin:\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Python/3.12/bin:\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Python/3.11/bin:\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Python/3.10/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        ]

        if engine == .qwen3ASR1_7B {
            let qwenCache = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first?
                .appendingPathComponent("SimulTrans/Models/qwen/huggingface", isDirectory: true)
                .path
                ?? "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Application Support/SimulTrans/Models/qwen/huggingface"
            environment["HF_HOME"] = qwenCache
            environment["HF_HUB_CACHE"] = "\(qwenCache)/hub"
        }

        return environment
    }
}

private final class LockedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func set(_ newValue: Value) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Value {
        lock.lock()
        let snapshot = value
        lock.unlock()
        return snapshot
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }

    mutating func appendLittleEndian<T: FixedWidthInteger>(_ value: T) {
        var littleEndianValue = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndianValue) { bytes in
            append(contentsOf: bytes)
        }
    }

    mutating func appendMultipartField(name: String, value: String, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendString("\(value)\r\n")
    }

    mutating func appendMultipartFile(name: String,
                                      filename: String,
                                      mimeType: String,
                                      fileURL: URL,
                                      boundary: String) throws {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: \(mimeType)\r\n\r\n")
        append(try Data(contentsOf: fileURL))
        appendString("\r\n")
    }
}
