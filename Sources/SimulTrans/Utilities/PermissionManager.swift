@preconcurrency import ApplicationServices
@preconcurrency import AVFoundation
import AppKit
import CoreGraphics
import Speech

@Observable
@MainActor
final class PermissionManager {
    enum Status {
        case granted
        case denied
        case notDetermined

        var isGranted: Bool { self == .granted }
    }

    var screenRecording: Status = .notDetermined
    var microphone: Status = .notDetermined
    var speechRecognition: Status = .notDetermined

    /// Re-read the current OS-level state for all three permissions.
    func refresh() {
        screenRecording = currentScreenRecordingStatus()
        microphone = currentMicrophoneStatus()
        speechRecognition = currentSpeechRecognitionStatus()
    }

    // MARK: - Screen recording

    private func currentScreenRecordingStatus() -> Status {
        // CGPreflightScreenCaptureAccess() returns true only when access is granted.
        // There is no "denied" vs "not determined" distinction at this API level —
        // we treat anything other than `true` as `notDetermined` so the UI offers a Grant button.
        CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
    }

    func requestScreenRecording() {
        _ = CGRequestScreenCaptureAccess()
        pollStatus { [weak self] in
            self?.screenRecording = self?.currentScreenRecordingStatus() ?? .notDetermined
            return self?.screenRecording == .granted
        }
    }

    // MARK: - Microphone

    private func currentMicrophoneStatus() -> Status {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:                 return .granted
        case .denied, .restricted:        return .denied
        case .notDetermined:              return .notDetermined
        @unknown default:                 return .notDetermined
        }
    }

    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] _ in
            Task { @MainActor in
                self?.microphone = self?.currentMicrophoneStatus() ?? .notDetermined
            }
        }
    }

    // MARK: - Speech recognition

    private func currentSpeechRecognitionStatus() -> Status {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:                 return .granted
        case .denied, .restricted:        return .denied
        case .notDetermined:              return .notDetermined
        @unknown default:                 return .notDetermined
        }
    }

    func requestSpeechRecognition() {
        SFSpeechRecognizer.requestAuthorization { [weak self] _ in
            Task { @MainActor in
                self?.speechRecognition = self?.currentSpeechRecognitionStatus() ?? .notDetermined
            }
        }
    }

    // MARK: - Polling

    /// Polls every second for up to 30 s, calling `tick()`. Stops once it returns true.
    private func pollStatus(tick: @escaping @MainActor () -> Bool) {
        Task { @MainActor in
            for _ in 0..<30 {
                try? await Task.sleep(for: .seconds(1))
                if tick() { return }
            }
        }
    }
}
