import AppKit
import SwiftUI
import UniformTypeIdentifiers
@preconcurrency import Translation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayPanel: OverlayPanel?
    private var controlWindow: NSWindow?
    private var isTranslatingPartial = false
    private var pendingTranslation = false
    private var latestRecognitionUpdate: RecognitionUpdate?
    private var provisionalEntryIndex: Int?
    private var provisionalSnapshotText: String = ""

    let appState = AppState()
    let audioRecognizer = SystemAudioRecognizer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        showControlWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Control Window

    private func showControlWindow() {
        let controlView = ControlWindowView(
            appState: appState,
            onStart: { [weak self] in self?.startTranslation() },
            onStop: { [weak self] in self?.stopTranslation() },
            onExport: { [weak self] in self?.exportTranscript() },
            onClear: { [weak self] in self?.clearTranscript() }
        )
        let hostingView = NSHostingView(rootView: controlView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 340),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SimulTrans 同传"
        window.contentView = hostingView
        window.center()
        window.makeKeyAndOrderFront(nil)
        controlWindow = window
    }

    // MARK: - Translation Pipeline

    func startTranslation() {
        appState.updateTranslationConfig()
        latestRecognitionUpdate = nil
        provisionalEntryIndex = nil
        provisionalSnapshotText = ""

        audioRecognizer.onResult = { [weak self] update in
            guard let self else { return }
            self.latestRecognitionUpdate = update

            if update.isFinal {
                self.handleFinalRecognitionUpdate(update)
            } else {
                self.handlePartialRecognitionUpdate(update)
            }
        }

        audioRecognizer.onError = { [weak self] error in
            self?.appState.errorMessage = error
        }

        audioRecognizer.onUtteranceBoundary = { [weak self] in
            self?.commitCurrentLiveSegmentAsProvisional()
        }

        let sourceLocale = Locale(identifier: appState.sourceLanguage.minimalIdentifier)
        let source: SystemAudioRecognizer.AudioSource = appState.audioSource == .microphone ? .microphone : .system
        audioRecognizer.start(locale: sourceLocale, source: source)
        appState.isRunning = true
        appState.errorMessage = nil
        showOverlay()
    }

    func stopTranslation() {
        // Save any remaining text
        if !appState.currentOriginalText.isEmpty {
            finalizeLiveEntry(text: appState.currentOriginalText)
        }

        isTranslatingPartial = false
        pendingTranslation = false
        latestRecognitionUpdate = nil
        provisionalEntryIndex = nil
        provisionalSnapshotText = ""
        audioRecognizer.stop()
        appState.isRunning = false
    }

    func clearTranscript() {
        appState.transcriptEntries.removeAll()
        appState.currentOriginalText = ""
        appState.currentTranslatedText = ""
    }

    func exportTranscript() {
        let entries = appState.transcriptEntries
        guard !entries.isEmpty else { return }

        let panel = NSSavePanel()
        panel.title = "保存会议记录"
        panel.nameFieldStringValue = "SimulTrans_\(Self.dateString()).txt"
        panel.allowedContentTypes = [.plainText]

        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            let text = Self.formatTranscript(entries: entries)
            try? text.write(to: url, atomically: true, encoding: .utf8)
            // Also open the file
            NSWorkspace.shared.open(url)
        }
    }

    private static func dateString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }

    private static func formatTranscript(entries: [TranscriptEntry]) -> String {
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "HH:mm:ss"

        var lines: [String] = []
        lines.append("SimulTrans 会议记录")
        lines.append("导出时间: \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .medium))")
        if let first = entries.first, let last = entries.last {
            lines.append("会议时段: \(timeFmt.string(from: first.timestamp)) ~ \(timeFmt.string(from: last.timestamp))")
        }
        lines.append(String(repeating: "─", count: 50))
        lines.append("")

        for (i, entry) in entries.enumerated() {
            let time = timeFmt.string(from: entry.timestamp)
            lines.append("[\(i + 1)] \(time)")
            lines.append("原文: \(entry.originalText)")
            if let translated = entry.translatedText {
                lines.append("译文: \(translated)")
            }
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Translates the latest partial text. When done, checks if newer text
    /// arrived during translation and translates again — no cancellation.
    private func translateLatestPartial(session: TranslationSession) {
        isTranslatingPartial = true
        pendingTranslation = false

        Task { @MainActor in
            let textToTranslate = self.appState.currentOriginalText
            guard !textToTranslate.isEmpty else {
                self.isTranslatingPartial = false
                return
            }

            if let response = try? await session.translate(textToTranslate) {
                self.appState.currentTranslatedText = response.targetText
            }

            // If new text arrived while we were translating, translate again
            if self.pendingTranslation, self.appState.isRunning {
                self.translateLatestPartial(session: session)
            } else {
                self.isTranslatingPartial = false
            }
        }
    }

    private func appendHistoryEntry(text: String, translated: String?) -> Int? {
        let trimmedOriginal = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOriginal.isEmpty else { return nil }
        return appState.appendEntry(original: trimmedOriginal,
                                    translated: translated?.isEmpty == false ? translated : nil)
    }

    private func finalizeLiveEntry(text: String) {
        isTranslatingPartial = false
        pendingTranslation = false

        guard let entryIndex = appendHistoryEntry(text: text, translated: appState.currentTranslatedText) else {
            return
        }
        appState.currentOriginalText = ""
        appState.currentTranslatedText = ""

        let sourceText = appState.transcriptEntries[entryIndex].originalText
        print("[SimulTrans] Saved entry #\(entryIndex + 1): \(sourceText.prefix(30))...")
        requestEntryTranslation(index: entryIndex, sourceText: sourceText)
    }

    private func commitCurrentLiveSegmentAsProvisional() {
        let liveText = appState.currentOriginalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !liveText.isEmpty, provisionalEntryIndex == nil else { return }

        isTranslatingPartial = false
        pendingTranslation = false

        guard let entryIndex = appendHistoryEntry(text: liveText, translated: appState.currentTranslatedText) else {
            return
        }
        provisionalEntryIndex = entryIndex
        provisionalSnapshotText = latestRecognitionUpdate?.text ?? liveText
        appState.currentOriginalText = ""
        appState.currentTranslatedText = ""

        let sourceText = appState.transcriptEntries[entryIndex].originalText
        print("[SimulTrans] Provisional entry #\(entryIndex + 1): \(sourceText.prefix(30))...")
        requestEntryTranslation(index: entryIndex, sourceText: sourceText)
    }

    private func handlePartialRecognitionUpdate(_ update: RecognitionUpdate) {
        let fullText = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fullText.isEmpty else {
            appState.currentOriginalText = ""
            appState.currentTranslatedText = ""
            return
        }

        if let currentProvisionalEntryIndex = provisionalEntryIndex {
            if !provisionalSnapshotText.isEmpty, update.text.hasPrefix(provisionalSnapshotText) {
                let suffix = String(update.text.dropFirst(provisionalSnapshotText.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                appState.currentOriginalText = suffix
                requestLiveTranslationIfNeeded(suffix)
                return
            }

            if looksLikeSameUtterance(previous: provisionalSnapshotText, current: update.text) {
                updateProvisionalEntry(index: currentProvisionalEntryIndex, text: fullText)
                provisionalSnapshotText = update.text
                appState.currentOriginalText = ""
                appState.currentTranslatedText = ""
                requestEntryTranslation(index: currentProvisionalEntryIndex, sourceText: fullText)
                return
            }

            provisionalEntryIndex = nil
            provisionalSnapshotText = ""
        }

        appState.currentOriginalText = fullText
        requestLiveTranslationIfNeeded(fullText)
    }

    private func handleFinalRecognitionUpdate(_ update: RecognitionUpdate) {
        let finalText = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalText.isEmpty else {
            provisionalEntryIndex = nil
            provisionalSnapshotText = ""
            appState.currentOriginalText = ""
            appState.currentTranslatedText = ""
            return
        }

        if let provisionalEntryIndex {
            updateProvisionalEntry(index: provisionalEntryIndex, text: finalText)
            requestEntryTranslation(index: provisionalEntryIndex, sourceText: finalText)
        } else {
            finalizeLiveEntry(text: finalText)
        }

        provisionalEntryIndex = nil
        provisionalSnapshotText = ""
        latestRecognitionUpdate = nil
        appState.currentOriginalText = ""
        appState.currentTranslatedText = ""
    }

    private func updateProvisionalEntry(index: Int, text: String) {
        guard index < appState.transcriptEntries.count else { return }
        appState.transcriptEntries[index].originalText = text
    }

    private func requestLiveTranslationIfNeeded(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            appState.currentTranslatedText = ""
            return
        }

        guard let session = appState.translationSession else { return }
        if !isTranslatingPartial {
            translateLatestPartial(session: session)
        } else {
            pendingTranslation = true
        }
    }

    private func requestEntryTranslation(index: Int, sourceText: String) {
        guard let session = appState.translationSession else { return }
        Task { @MainActor in
            if let response = try? await session.translate(sourceText),
               index < self.appState.transcriptEntries.count,
               self.appState.transcriptEntries[index].originalText == sourceText {
                self.appState.transcriptEntries[index].translatedText = response.targetText
            }
        }
    }

    private func looksLikeSameUtterance(previous: String, current: String) -> Bool {
        let previousTrimmed = previous.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentTrimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !previousTrimmed.isEmpty, !currentTrimmed.isEmpty else { return false }
        if currentTrimmed.hasPrefix(previousTrimmed) || previousTrimmed.hasPrefix(currentTrimmed) {
            return true
        }

        let commonPrefix = commonPrefixLength(previousTrimmed, currentTrimmed)
        let minLength = min(previousTrimmed.count, currentTrimmed.count)
        guard minLength > 0 else { return false }
        return Double(commonPrefix) / Double(minLength) >= 0.8
    }

    private func commonPrefixLength(_ lhs: String, _ rhs: String) -> Int {
        var count = 0
        for (left, right) in zip(lhs, rhs) {
            guard left == right else { break }
            count += 1
        }
        return count
    }

    // MARK: - Overlay

    private func showOverlay() {
        if overlayPanel == nil {
            overlayPanel = OverlayPanel(contentRect: .zero)
            let view = OverlayContentView(onExport: { [weak self] in
                self?.exportTranscript()
            }).environment(appState)
            let hostingView = NSHostingView(rootView: AnyView(view))
            overlayPanel?.contentView = hostingView
        }
        overlayPanel?.orderFrontRegardless()
    }

    private func hideOverlay() {
        overlayPanel?.orderOut(nil)
    }
}
