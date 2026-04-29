import AppKit
import SwiftUI
import UniformTypeIdentifiers
@preconcurrency import Translation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlayPanel: OverlayPanel?
    private var controlWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var statusItem: NSStatusItem?
    private var statusPopover: NSPopover?
    private let permissions = PermissionManager()
    private static let onboardingDefaultsKey = "simultrans.onboarding.completed.v1"
    private var isTranslatingPartial = false
    private var pendingTranslation = false
    private var latestRecognitionUpdate: RecognitionUpdate?
    private var liveRecognitionText: String = ""
    private var liveDisplayRevision: Int = 0
    private var provisionalEntryIndex: Int?
    private var provisionalSnapshotText: String = ""
    private let liveSegmentDebouncer = Debouncer(delay: 1.0)

    let appState = AppState()
    let audioRecognizer = SystemAudioRecognizer()

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppFontRegistry.registerBundledFonts()
        NSApp.appearance = appState.appearancePreference.nsAppearance
        installMainMenu()
        showControlWindow()
        permissions.refresh()
        applyMenuBarIconPreference()
        observeMenuBarIconPreference()
        observeAppDisplayLanguage()

        if !UserDefaults.standard.bool(forKey: Self.onboardingDefaultsKey) {
            // Defer briefly so the control window is visible behind the onboarding sheet.
            DispatchQueue.main.async { [weak self] in
                self?.showOnboardingWindow()
            }
        }
    }

    // MARK: - Menu

    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: appState.localizedAppString("About SimulTrans"),
                                   action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
                                   keyEquivalent: ""))
        appMenu.addItem(.separator())
        let settingsItem = NSMenuItem(title: appState.localizedAppString("Settings…"),
                                      action: #selector(openSettings),
                                      keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: appState.localizedAppString("Hide SimulTrans"),
                                   action: #selector(NSApplication.hide(_:)),
                                   keyEquivalent: "h"))
        let hideOthers = NSMenuItem(title: appState.localizedAppString("Hide Others"),
                                    action: #selector(NSApplication.hideOtherApplications(_:)),
                                    keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(NSMenuItem(title: appState.localizedAppString("Show All"),
                                   action: #selector(NSApplication.unhideAllApplications(_:)),
                                   keyEquivalent: ""))
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: appState.localizedAppString("Quit SimulTrans"),
                                   action: #selector(NSApplication.terminate(_:)),
                                   keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        NSApp.mainMenu = mainMenu
    }

    @objc private func openSettings() {
        showSettingsWindow()
    }

    private func showSettingsWindow() {
        if let settingsWindow {
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView().environment(appState)
        let hostingView = NSHostingView(rootView: settingsView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0,
                                width: STTheme.settingsWindowSize.width,
                                height: STTheme.settingsWindowSize.height),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = appState.localizedAppString("SimulTrans Settings")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // MARK: - Menubar status item

    private func observeMenuBarIconPreference() {
        withObservationTracking { [appState] in
            _ = appState.showMenuBarIcon
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.applyMenuBarIconPreference()
                self.observeMenuBarIconPreference()
            }
        }
    }

    private func observeAppDisplayLanguage() {
        withObservationTracking { [appState] in
            _ = appState.appDisplayLanguage
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.refreshLocalizedChrome()
                self.observeAppDisplayLanguage()
            }
        }
    }

    private func refreshLocalizedChrome() {
        installMainMenu()
        settingsWindow?.title = appState.localizedAppString("SimulTrans Settings")
        onboardingWindow?.title = appState.localizedAppString("Welcome to SimulTrans")
    }

    private func applyMenuBarIconPreference() {
        if appState.showMenuBarIcon {
            installStatusItemIfNeeded()
        } else {
            removeStatusItem()
        }
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "SimulTrans")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(toggleStatusPopover(_:))
        }
        statusItem = item

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 320, height: 360)
        let popoverView = MenubarPopoverView(
            onToggle: { [weak self] in
                guard let self else { return }
                if self.appState.isRunning {
                    self.stopTranslation()
                } else {
                    self.startTranslation()
                }
            },
            onOpenWindow: { [weak self] in
                self?.statusPopover?.performClose(nil)
                self?.bringControlWindowForward()
            }
        ).environment(appState)
        popover.contentViewController = NSHostingController(rootView: popoverView)
        statusPopover = popover
    }

    private func removeStatusItem() {
        statusPopover?.performClose(nil)
        statusPopover = nil
        if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
    }

    @objc private func toggleStatusPopover(_ sender: Any?) {
        guard let button = statusItem?.button, let popover = statusPopover else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func bringControlWindowForward() {
        if let controlWindow {
            controlWindow.makeKeyAndOrderFront(nil)
        } else {
            showControlWindow()
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Onboarding

    private func showOnboardingWindow() {
        if let onboardingWindow {
            onboardingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = OnboardingView(
            permissions: permissions,
            onContinue: { [weak self] in self?.completeOnboarding() },
            onSkip:     { [weak self] in self?.completeOnboarding() }
        ).environment(appState)
        let hostingView = NSHostingView(rootView: view)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = appState.localizedAppString("Welcome to SimulTrans")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingDefaultsKey)
        onboardingWindow?.close()
        onboardingWindow = nil
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
            contentRect: NSRect(x: 0, y: 0, width: STTheme.controlWindowSize.width, height: STTheme.controlWindowSize.height),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "SimulTrans"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hostingView
        window.center()
        window.makeKeyAndOrderFront(nil)
        controlWindow = window
    }

    // MARK: - Translation Pipeline

    func startTranslation() {
        appState.updateTranslationConfig()
        latestRecognitionUpdate = nil
        liveRecognitionText = ""
        liveDisplayRevision = 0
        provisionalEntryIndex = nil
        provisionalSnapshotText = ""
        appState.isRunning = true
        appState.sessionStartedAt = Date()
        appState.errorMessage = nil
        appState.resetRecognitionDebug(keepHistory: false)
        appState.recognitionPhase = "listening"

        audioRecognizer.onResult = { [weak self] update in
            guard let self else { return }
            let previousUpdate = self.latestRecognitionUpdate
            self.latestRecognitionUpdate = update

            if update.isFinal {
                self.handleFinalRecognitionUpdate(update)
            } else {
                self.handlePartialRecognitionUpdate(update, previousUpdate: previousUpdate)
            }
        }

        audioRecognizer.onError = { [weak self] error in
            self?.appState.errorMessage = error
        }

        audioRecognizer.onUtteranceBoundary = nil

        let sourceLocale = Locale(identifier: appState.sourceLanguage.minimalIdentifier)
        let source: SystemAudioRecognizer.AudioSource = appState.audioSource == .microphone ? .microphone : .system
        audioRecognizer.start(locale: sourceLocale, source: source)
        showOverlay()
    }

    func stopTranslation() {
        // Save any remaining text
        if !appState.currentOriginalText.isEmpty {
            finalizeLiveEntry(text: appState.currentOriginalText, recognitionText: liveRecognitionText)
        }

        isTranslatingPartial = false
        pendingTranslation = false
        latestRecognitionUpdate = nil
        liveRecognitionText = ""
        liveDisplayRevision = 0
        provisionalEntryIndex = nil
        provisionalSnapshotText = ""
        audioRecognizer.stop()
        appState.isRunning = false
        appState.sessionStartedAt = nil
        appState.recognitionPhase = "stopped"
    }

    func clearTranscript() {
        appState.transcriptEntries.removeAll()
        appState.currentOriginalText = ""
        appState.currentTranslatedText = ""
        liveRecognitionText = ""
        liveDisplayRevision = 0
        provisionalEntryIndex = nil
        provisionalSnapshotText = ""
        appState.resetRecognitionDebug(keepHistory: false)
    }

    func exportTranscript() {
        let entries = appState.transcriptEntries
        guard !entries.isEmpty else { return }

        let panel = NSSavePanel()
        panel.title = appState.localizedAppString("Save Transcript")
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
        lines.append("SimulTrans Transcript")
        lines.append("Exported: \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .medium))")
        if let first = entries.first, let last = entries.last {
            lines.append("Recorded range: \(timeFmt.string(from: first.timestamp)) - \(timeFmt.string(from: last.timestamp))")
        }
        lines.append(String(repeating: "─", count: 50))
        lines.append("")

        for (i, entry) in entries.enumerated() {
            let time = timeFmt.string(from: entry.timestamp)
            lines.append("[\(i + 1)] \(time)")
            lines.append("Source: \(entry.originalText)")
            if let translated = entry.translatedText {
                lines.append("Translation: \(translated)")
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
            let textToTranslate = self.liveRecognitionText.trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func finalizeLiveEntry(text: String, recognitionText: String? = nil) {
        isTranslatingPartial = false
        pendingTranslation = false

        guard let entryIndex = appendHistoryEntry(text: text, translated: appState.currentTranslatedText) else {
            return
        }
        clearLiveEntry()

        let entryID = appState.transcriptEntries[entryIndex].id
        let sourceText = appState.transcriptEntries[entryIndex].originalText
        print("[SimulTrans] Saved entry #\(entryIndex + 1): \(sourceText.prefix(30))...")
        let translationSource = recognitionText?.trimmingCharacters(in: .whitespacesAndNewlines)
        requestEntryTranslation(index: entryIndex,
                                entryID: entryID,
                                sourceText: (translationSource?.isEmpty == false ? translationSource! : sourceText))
    }

    private func commitCurrentLiveSegmentAsProvisional(snapshotText: String? = nil) {
        let liveText = appState.currentOriginalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !liveText.isEmpty, provisionalEntryIndex == nil else { return }

        isTranslatingPartial = false
        pendingTranslation = false

        guard let entryIndex = appendHistoryEntry(text: liveText, translated: appState.currentTranslatedText) else {
            return
        }
        provisionalEntryIndex = entryIndex
        let snapshot = snapshotText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackSnapshot = liveRecognitionText.trimmingCharacters(in: .whitespacesAndNewlines)
        provisionalSnapshotText = snapshot?.isEmpty == false ? snapshot! : fallbackSnapshot
        clearLiveEntry()

        let entryID = appState.transcriptEntries[entryIndex].id
        let sourceText = appState.transcriptEntries[entryIndex].originalText
        print("[SimulTrans] Provisional entry #\(entryIndex + 1): \(sourceText.prefix(30))...")
        let translationSource = provisionalSnapshotText.isEmpty ? sourceText : provisionalSnapshotText
        requestEntryTranslation(index: entryIndex, entryID: entryID, sourceText: translationSource)
    }

    private func handlePartialRecognitionUpdate(_ update: RecognitionUpdate, previousUpdate: RecognitionUpdate?) {
        let fullText = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fullText.isEmpty else { return }
        updateDebugSurface(rawText: fullText, phase: "partial")

        // If the recognizer starts a fresh timeline after we already committed a
        // provisional entry, drop the old provisional context immediately so the
        // next utterance cannot get swallowed by overlap heuristics.
        if provisionalEntryIndex != nil,
           didRecognitionTimelineReset(previousUpdate: previousUpdate, currentUpdate: update) {
            provisionalEntryIndex = nil
            provisionalSnapshotText = ""
        }

        if shouldCommitExistingLiveEntry(currentUpdate: update, previousUpdate: previousUpdate) {
            commitCurrentLiveSegmentAsProvisional(snapshotText: liveRecognitionText.isEmpty ? previousUpdate?.text : liveRecognitionText)
        }

        let candidateText = effectiveIncomingText(from: fullText)
        guard !candidateText.isEmpty else {
            appState.effectiveRecognitionText = ""
            recordDebugSnapshot(phase: "partial", rawText: fullText, effectiveText: "")
            return
        }

        let fragmentToAppend = appendableSuffix(existing: appState.currentOriginalText, incoming: candidateText)
        appendLiveOriginalText(fragmentToAppend, fallbackText: candidateText)
        requestLiveTranslationIfNeeded(candidateText)
        appState.effectiveRecognitionText = candidateText
        recordDebugSnapshot(phase: "partial", rawText: fullText, effectiveText: candidateText)
        scheduleStableLiveCommitIfNeeded()
    }

    private func handleFinalRecognitionUpdate(_ update: RecognitionUpdate) {
        let finalText = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalText.isEmpty else {
            provisionalEntryIndex = nil
            provisionalSnapshotText = ""
            clearLiveEntry()
            appState.recognitionPhase = "listening"
            return
        }
        updateDebugSurface(rawText: finalText, phase: "final")

        let entryToRefresh: (index: Int, entryID: UUID)? = {
            guard let provisionalEntryIndex, provisionalEntryIndex < appState.transcriptEntries.count else { return nil }
            return (provisionalEntryIndex, appState.transcriptEntries[provisionalEntryIndex].id)
        }()

        let finalCandidateText = effectiveIncomingText(from: finalText)
        if !finalCandidateText.isEmpty {
            let fragmentToAppend = appendableSuffix(existing: appState.currentOriginalText, incoming: finalCandidateText)
            appendLiveOriginalText(fragmentToAppend, fallbackText: finalCandidateText)
            liveRecognitionText = finalCandidateText
            appState.effectiveRecognitionText = finalCandidateText
            recordDebugSnapshot(phase: "final", rawText: finalText, effectiveText: finalCandidateText)
        } else if let entryToRefresh {
            requestEntryTranslation(index: entryToRefresh.index, entryID: entryToRefresh.entryID, sourceText: finalText)
            appState.effectiveRecognitionText = ""
            recordDebugSnapshot(phase: "final", rawText: finalText, effectiveText: "")
        }

        let textToFinalize = appState.currentOriginalText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !textToFinalize.isEmpty {
            let recognitionSnapshot = liveRecognitionText.trimmingCharacters(in: .whitespacesAndNewlines)
            finalizeLiveEntry(text: textToFinalize,
                              recognitionText: recognitionSnapshot.isEmpty ? finalText : recognitionSnapshot)
        }

        provisionalEntryIndex = nil
        provisionalSnapshotText = ""
        latestRecognitionUpdate = nil
        clearLiveEntry()
        appState.recognitionPhase = "listening"
    }

    private func requestLiveTranslationIfNeeded(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            appState.currentTranslatedText = ""
            liveRecognitionText = ""
            return
        }

        liveRecognitionText = trimmedText
        guard let session = appState.translationSession else { return }
        if !isTranslatingPartial {
            translateLatestPartial(session: session)
        } else {
            pendingTranslation = true
        }
    }

    private func requestEntryTranslation(index: Int, entryID: UUID, sourceText: String) {
        guard let session = appState.translationSession else { return }
        Task { @MainActor in
            if let response = try? await session.translate(sourceText),
               index < self.appState.transcriptEntries.count,
               self.appState.transcriptEntries[index].id == entryID {
                self.appState.transcriptEntries[index].translatedText = response.targetText
            }
        }
    }

    private func shouldCommitExistingLiveEntry(currentUpdate: RecognitionUpdate,
                                               previousUpdate: RecognitionUpdate?) -> Bool {
        let currentLiveText = appState.currentOriginalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard provisionalEntryIndex == nil, !currentLiveText.isEmpty else { return false }
        return didRecognitionTimelineReset(previousUpdate: previousUpdate, currentUpdate: currentUpdate)
    }

    private func didRecognitionTimelineReset(previousUpdate: RecognitionUpdate?,
                                             currentUpdate: RecognitionUpdate) -> Bool {
        guard let previousUpdate else { return false }

        let previousDuration = previousUpdate.segments.last?.endTime ?? 0
        let currentDuration = currentUpdate.segments.last?.endTime ?? 0
        let currentFirstTimestamp = currentUpdate.segments.first?.timestamp ?? 0

        guard previousDuration >= 1.0 else { return false }
        guard currentDuration > 0, currentFirstTimestamp < 0.35 else { return false }

        return currentDuration + 0.6 < previousDuration
    }

    private static func isSentenceBoundaryCharacter(_ character: Character) -> Bool {
        ".!?。！？".contains(character)
    }

    private func effectiveIncomingText(from fullText: String) -> String {
        let trimmedFullText = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFullText.isEmpty else { return "" }
        guard provisionalEntryIndex != nil, !provisionalSnapshotText.isEmpty else { return trimmedFullText }

        if trimmedFullText.hasPrefix(provisionalSnapshotText) {
            return String(trimmedFullText.dropFirst(provisionalSnapshotText.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let overlap = suffixPrefixOverlap(previous: provisionalSnapshotText, current: trimmedFullText)
        if overlap > 0 {
            return String(trimmedFullText.dropFirst(overlap))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if forwardMatchCoverage(existing: provisionalSnapshotText, incoming: trimmedFullText) >= 0.8 {
            return ""
        }

        provisionalEntryIndex = nil
        provisionalSnapshotText = ""
        return trimmedFullText
    }

    private func appendableSuffix(existing: String, incoming: String) -> String {
        let trimmedExisting = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedIncoming = incoming.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedIncoming.isEmpty else { return "" }
        guard !trimmedExisting.isEmpty else { return trimmedIncoming }

        if trimmedIncoming.hasPrefix(trimmedExisting) {
            return String(trimmedIncoming.dropFirst(trimmedExisting.count))
        }

        if trimmedExisting.hasPrefix(trimmedIncoming) {
            return ""
        }

        let overlap = suffixPrefixOverlap(previous: trimmedExisting, current: trimmedIncoming)
        if overlap >= max(2, min(trimmedExisting.count, trimmedIncoming.count) / 3) {
            return String(trimmedIncoming.dropFirst(overlap))
        }

        return forwardAlignedTail(existing: trimmedExisting, incoming: trimmedIncoming) ?? ""
    }

    private func suffixPrefixOverlap(previous: String, current: String) -> Int {
        let previousCharacters = Array(previous)
        let currentCharacters = Array(current)
        let maxOverlap = min(previousCharacters.count, currentCharacters.count)

        guard maxOverlap > 0 else { return 0 }

        for overlap in stride(from: maxOverlap, through: 1, by: -1) {
            let previousSuffix = previousCharacters[(previousCharacters.count - overlap)...]
            let currentPrefix = currentCharacters[..<overlap]
            if Array(previousSuffix) == Array(currentPrefix) {
                return overlap
            }
        }

        return 0
    }

    private func appendLiveOriginalText(_ fragment: String, fallbackText: String) {
        let currentText = appState.currentOriginalText.trimmingCharacters(in: .whitespacesAndNewlines)
        if currentText.isEmpty {
            let seededText = fallbackText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !seededText.isEmpty else { return }
            appState.currentOriginalText = seededText
            liveDisplayRevision += 1
            return
        }

        let normalizedFragment = fragment.trimmingCharacters(in: .newlines)
        guard !normalizedFragment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if let lastCharacter = appState.currentOriginalText.last,
           let firstCharacter = normalizedFragment.first,
           !lastCharacter.isWhitespace,
           !firstCharacter.isWhitespace,
           shouldInsertSpace(between: lastCharacter, and: firstCharacter) {
            appState.currentOriginalText += " "
        }

        appState.currentOriginalText += normalizedFragment
        liveDisplayRevision += 1
    }

    private func shouldInsertSpace(between left: Character, and right: Character) -> Bool {
        left.isASCIIWordLike && right.isASCIIWordLike
    }

    private func forwardAlignedTail(existing: String, incoming: String) -> String? {
        let match = longestCommonSubsequenceMatch(existing: existing, incoming: incoming)
        guard match.coverage >= 0.7, let lastMatchedIncomingIndex = match.lastMatchedIncomingIndex else {
            return nil
        }

        let incomingCharacters = Array(incoming)
        guard lastMatchedIncomingIndex + 1 < incomingCharacters.count else { return "" }
        return String(incomingCharacters[(lastMatchedIncomingIndex + 1)...])
    }

    private func forwardMatchCoverage(existing: String, incoming: String) -> Double {
        longestCommonSubsequenceMatch(existing: existing, incoming: incoming).coverage
    }

    private func longestCommonSubsequenceMatch(existing: String, incoming: String) -> (coverage: Double, lastMatchedIncomingIndex: Int?) {
        let existingCharacters = Array(existing)
        let incomingCharacters = Array(incoming)
        guard !existingCharacters.isEmpty, !incomingCharacters.isEmpty else { return (0, nil) }

        var dp = Array(repeating: Array(repeating: 0, count: incomingCharacters.count + 1),
                       count: existingCharacters.count + 1)

        for existingIndex in 0..<existingCharacters.count {
            for incomingIndex in 0..<incomingCharacters.count {
                if existingCharacters[existingIndex] == incomingCharacters[incomingIndex] {
                    dp[existingIndex + 1][incomingIndex + 1] = dp[existingIndex][incomingIndex] + 1
                } else {
                    dp[existingIndex + 1][incomingIndex + 1] = max(dp[existingIndex][incomingIndex + 1],
                                                                   dp[existingIndex + 1][incomingIndex])
                }
            }
        }

        let matchCount = dp[existingCharacters.count][incomingCharacters.count]
        guard matchCount > 0 else { return (0, nil) }

        var existingIndex = existingCharacters.count
        var incomingIndex = incomingCharacters.count
        var matchedIncomingIndices: [Int] = []

        while existingIndex > 0, incomingIndex > 0 {
            if existingCharacters[existingIndex - 1] == incomingCharacters[incomingIndex - 1] {
                matchedIncomingIndices.append(incomingIndex - 1)
                existingIndex -= 1
                incomingIndex -= 1
            } else if dp[existingIndex - 1][incomingIndex] >= dp[existingIndex][incomingIndex - 1] {
                existingIndex -= 1
            } else {
                incomingIndex -= 1
            }
        }

        let coverage = Double(matchCount) / Double(existingCharacters.count)
        return (coverage, matchedIncomingIndices.first)
    }

    private func clearLiveEntry() {
        appState.currentOriginalText = ""
        appState.currentTranslatedText = ""
        liveRecognitionText = ""
        liveDisplayRevision = 0
    }

    private func updateDebugSurface(rawText: String, phase: String) {
        appState.rawRecognitionText = rawText
        appState.recognitionPhase = phase
        if phase == "final" {
            appState.lastFinalRecognitionText = rawText
        }
    }

    private func recordDebugSnapshot(phase: String, rawText: String, effectiveText: String) {
        appState.recordRecognitionDebug(phase: phase,
                                        rawText: rawText,
                                        effectiveText: effectiveText,
                                        displayedText: appState.currentOriginalText,
                                        translatedText: appState.currentTranslatedText)
    }

    private func scheduleStableLiveCommitIfNeeded() {
        let displaySnapshot = appState.currentOriginalText.trimmingCharacters(in: .whitespacesAndNewlines)
        let recognitionLengthSnapshot = liveRecognitionText.utf16.count
        let displayRevisionSnapshot = liveDisplayRevision

        guard provisionalEntryIndex == nil, !displaySnapshot.isEmpty, recognitionLengthSnapshot > 0 else { return }

        Task {
            await liveSegmentDebouncer.debounce { [weak self, displaySnapshot, recognitionLengthSnapshot, displayRevisionSnapshot] in
                guard let self else { return }
                await MainActor.run {
                    guard self.appState.isRunning else { return }
                    guard self.provisionalEntryIndex == nil else { return }

                    let currentDisplay = self.appState.currentOriginalText.trimmingCharacters(in: .whitespacesAndNewlines)

                    guard currentDisplay == displaySnapshot,
                          self.liveDisplayRevision == displayRevisionSnapshot,
                          self.liveRecognitionText.utf16.count == recognitionLengthSnapshot else { return }

                    self.commitCurrentLiveSegmentAsProvisional(snapshotText: self.liveRecognitionText)
                }
            }
        }
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

private extension Character {
    var isASCIIWordLike: Bool {
        unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) && scalar.isASCII
        }
    }
}
