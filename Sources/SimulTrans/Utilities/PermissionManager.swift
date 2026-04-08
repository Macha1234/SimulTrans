@preconcurrency import ApplicationServices
import AppKit

@Observable
@MainActor
final class PermissionManager {
    var accessibilityGranted: Bool = false

    func checkAccessibility() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options: NSDictionary = [key: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        // Poll for permission change
        Task {
            for _ in 0..<30 {
                try? await Task.sleep(for: .seconds(1))
                if AXIsProcessTrusted() {
                    accessibilityGranted = true
                    return
                }
            }
        }
    }
}
