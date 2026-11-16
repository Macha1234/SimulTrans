import AppKit
import SwiftUI
import UniformTypeIdentifiers
@preconcurrency import Translation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
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
    private var liveSegmentID = UUID()
    private var translatedLiveSource = ""
    private var liveTranslationRevision: Int = 0
    private var activeLiveTranslationRevision: Int?
    private var qwenStartupToken: UUID?
    private var activeRecognitionRunID = UUID()
    private var translationRunID = UUID()
    private var entryTranslationTasks: [UUID: Task<Void, Never>] = [:]
    private var terminationInProgress = false

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

    func applicationWillTerminate(_ notification: Notification) {
        entryTranslationTasks.values.forEach { $0.cancel() }
        audioRecognizer.stop()
        LocalSpeechRecognizer.stopLocalASRServers()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminationInProgress else { return .terminateLater }
        terminationInProgress = true

        entryTranslationTasks.values.forEach { $0.cancel() }
        entryTranslationTasks.removeAll()
        audioRecognizer.stop()
        LocalSpeechRecognizer.stopLocalASRServers()
        appState.isRunning = false
        appState.sessionStartedAt = nil
        appState.recognitionPhase = "stopped"

        // Keep the process alive until the Mini PC confirms that both GPU models
        // have been released. A fire-and-forget Task in applicationWillTerminate
        // is too late because macOS can tear down the process first.
        Task {
            await RemoteQwenASRService.shared.stopImmediately()
            await OllamaTranslationRefiner.shared.unloadImmediately()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if sender === overlayPanel {
            hideOverlay()
            return false
        }
        guard sender === controlWindow else { return true }
        NSApp.terminate(nil)
        return false
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
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = appState.localizedAppString("SimulTrans Settings")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = false
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.minSize = NSSize(width: 760, height: 580)
        window.contentView = hostingView
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
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
        popover.contentSize = NSSize(width: 360, height: 410)
        let popoverView = MenubarPopoverView(
            onToggle: { [weak self] in
                guard let self else { return }
                if self.appState.isRunning {
                    self.stopTranslation()
                } else {
                    self.startTranslation()
                }
            },
            onToggleOverlay: { [weak self] in
                self?.toggleOverlayVisibility()
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
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 660),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = appState.localizedAppString("Welcome to SimulTrans")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
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
            onClear: { [weak self] in self?.clearTranscript() },
            onToggleOverlay: { [weak self] in self?.toggleOverlayVisibility() },
            onOpenSettings: { [weak self] in self?.showSettingsWindow() }
        )
        let hostingView = NSHostingView(rootView: controlView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: STTheme.controlWindowSize.width, height: STTheme.controlWindowSize.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
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
        window.minSize = STTheme.controlWindowMinSize
        window.contentView = hostingView
        window.delegate = self
        window.center()
        window.makeKeyAndOrderFront(nil)
        controlWindow = window
    }

    // MARK: - Translation Pipeline

    func startTranslation() {
        guard !appState.isRunning else { return }
        entryTranslationTasks.values.forEach { $0.cancel() }
        entryTranslationTasks.removeAll()
        translationRunID = UUID()
        activeRecognitionRunID = UUID()
        appState.updateTranslationConfig()
        latestRecognitionUpdate = nil
        liveRecognitionText = ""
        liveDisplayRevision = 0
        liveTranslationRevision &+= 1
        activeLiveTranslationRevision = nil
        isTranslatingPartial = false
        pendingTranslation = false
        appState.isRunning = true
        appState.sessionStartedAt = Date()
        appState.errorMessage = nil
        appState.resetRecognitionDebug(keepHistory: false)
        appState.recognitionPhase = "listening"

        if appState.recognitionEngine == .qwen3ASR1_7B {
            let startupToken = activeRecognitionRunID
            qwenStartupToken = startupToken
            appState.recognitionPhase = "starting Qwen on Mini PC"

            Task { [weak self] in
                do {
                    try await RemoteQwenASRService.shared.start()
                    guard let self,
                          self.appState.isRunning,
                          self.qwenStartupToken == startupToken else {
                        await RemoteQwenASRService.shared.stop()
                        return
                    }
                    self.qwenStartupToken = nil
                    self.beginRecognition(runID: startupToken)
                } catch {
                    guard let self,
                          self.appState.isRunning,
                          self.qwenStartupToken == startupToken else {
                        return
                    }
                    self.qwenStartupToken = nil
                    self.appState.errorMessage = "Could not start Qwen on the Mini PC: \(error.localizedDescription)"
                    self.appState.isRunning = false
                    self.appState.sessionStartedAt = nil
                    self.appState.recognitionPhase = "stopped"
                }
            }
        } else {
            beginRecognition(runID: activeRecognitionRunID)
        }
    }

    private func beginRecognition(runID: UUID) {
        audioRecognizer.onResult = { [weak self] update in
            guard let self, self.activeRecognitionRunID == runID else { return }
            if let timing = update.timing {
                self.appState.lastASRQueueMilliseconds = Int((timing.queueDuration * 1_000).rounded())
                self.appState.lastASRProcessingMilliseconds = Int((timing.processingDuration * 1_000).rounded())
            }
            let previousUpdate = self.latestRecognitionUpdate
            self.latestRecognitionUpdate = update

            if update.isFinal {
                self.handleFinalRecognitionUpdate(update, previousUpdate: previousUpdate)
            } else {
                self.handlePartialRecognitionUpdate(update, previousUpdate: previousUpdate)
            }
        }

        audioRecognizer.onError = { [weak self] error in
            guard let self,
                  self.activeRecognitionRunID == runID,
                  self.appState.isRunning else { return }
            self.appState.errorMessage = error
        }

        // Recognition text can stall while audio is still arriving. Only the
        // recognizer's final result (or an explicit timeline change) ends a row.
        audioRecognizer.onUtteranceBoundary = nil

        let sourceLocale = Locale(identifier: appState.sourceLanguage.minimalIdentifier)
        let source: SystemAudioRecognizer.AudioSource = appState.audioSource == .microphone ? .microphone : .system
        audioRecognizer.start(locale: sourceLocale, source: source, engine: appState.recognitionEngine)
        showOverlay()
    }

    func stopTranslation() {
        activeRecognitionRunID = UUID()
        // Save any remaining text
        if !appState.currentOriginalText.isEmpty {
            finalizeLiveEntry(text: appState.currentOriginalText, recognitionText: liveRecognitionText)
        }

        isTranslatingPartial = false
        pendingTranslation = false
        activeLiveTranslationRevision = nil
        latestRecognitionUpdate = nil
        liveRecognitionText = ""
        liveDisplayRevision = 0
        let shouldStopRemoteQwen = appState.recognitionEngine == .qwen3ASR1_7B || qwenStartupToken != nil
        qwenStartupToken = nil
        audioRecognizer.stop()
        appState.isRunning = false
        appState.sessionStartedAt = nil
        appState.recognitionPhase = "stopped"

        if shouldStopRemoteQwen {
            Task { await RemoteQwenASRService.shared.stop() }
        }
    }

    func clearTranscript() {
        entryTranslationTasks.values.forEach { $0.cancel() }
        entryTranslationTasks.removeAll()
        translationRunID = UUID()
        appState.transcriptEntries.removeAll()
        clearLiveEntry()
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
        let segmentID = liveSegmentID
        let textToTranslate = liveRecognitionText.trimmingCharacters(in: .whitespacesAndNewlines)
        let translationRevision = liveTranslationRevision
        let configRevision = appState.translationConfigurationRevision
        guard !textToTranslate.isEmpty else {
            isTranslatingPartial = false
            activeLiveTranslationRevision = nil
            return
        }

        isTranslatingPartial = true
        pendingTranslation = false
        activeLiveTranslationRevision = translationRevision

        Task { @MainActor in
            if let response = try? await session.translate(textToTranslate),
               self.appState.translationConfigurationRevision == configRevision,
               self.liveSegmentID == segmentID,
               // Qwen re-decodes the whole window, so earlier words can change; a
               // slightly stale translation beats discarding every result.
               !self.appState.currentOriginalText.isEmpty {
                self.translatedLiveSource = textToTranslate
                self.appState.currentTranslatedText = response.targetText
            }

            guard self.activeLiveTranslationRevision == translationRevision else { return }

            // If new text arrived while we were translating, translate again
            if self.pendingTranslation,
               self.appState.isRunning,
               !self.liveRecognitionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.isTranslatingPartial = false
                if let currentSession = self.appState.translationSession {
                    self.translateLatestPartial(session: currentSession)
                }
            } else {
                self.isTranslatingPartial = false
                self.activeLiveTranslationRevision = nil
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

        guard let entryIndex = appendHistoryEntry(text: text, translated: translatedLiveSource == text ? appState.currentTranslatedText : nil) else {
            return
        }
        clearLiveEntry()

        let entryID = appState.transcriptEntries[entryIndex].id
        let sourceText = appState.transcriptEntries[entryIndex].originalText
        print("[SimulTrans] Saved entry #\(entryIndex + 1): \(sourceText.prefix(30))...")
        let translationSource = recognitionText?.trimmingCharacters(in: .whitespacesAndNewlines)
        requestEntryTranslation(entryID: entryID,
                                sourceText: (translationSource?.isEmpty == false ? translationSource! : sourceText))
    }

    func handlePartialRecognitionUpdate(_ update: RecognitionUpdate, previousUpdate: RecognitionUpdate?) {
        let text = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        updateDebugSurface(rawText: text, phase: "partial")
        if !appState.currentOriginalText.isEmpty,
           didRecognitionWindowChange(previousUpdate: previousUpdate, currentUpdate: update) {
            finalizeLiveEntry(text: appState.currentOriginalText)
        }
        replaceLiveOriginalText(with: text)
        requestLiveTranslationIfNeeded(text)
        appState.effectiveRecognitionText = text
        recordDebugSnapshot(phase: "partial", rawText: text, effectiveText: text)
    }

    func handleFinalRecognitionUpdate(_ update: RecognitionUpdate,
                                      previousUpdate: RecognitionUpdate?) {
        let text = update.text.trimmingCharacters(in: .whitespacesAndNewlines)
        updateDebugSurface(rawText: text, phase: "final")
        if !text.isEmpty {
            replaceLiveOriginalText(with: text)
        }
        let finalText = appState.currentOriginalText
        if !finalText.isEmpty {
            finalizeLiveEntry(text: finalText)
        }
        latestRecognitionUpdate = nil
        clearLiveEntry()
        appState.effectiveRecognitionText = finalText
        recordDebugSnapshot(phase: "final", rawText: text, effectiveText: finalText)
        appState.recognitionPhase = "listening"
    }

    private func translationSessionReady() {
        if !appState.currentOriginalText.isEmpty {
            requestLiveTranslationIfNeeded(appState.currentOriginalText)
        }
        for entry in appState.transcriptEntries where entry.translatedText == nil {
            requestEntryTranslation(entryID: entry.id, sourceText: entry.originalText)
        }
    }

    private func requestLiveTranslationIfNeeded(_ text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            appState.currentTranslatedText = ""
            liveRecognitionText = ""
            liveTranslationRevision &+= 1
            return
        }

        if liveRecognitionText != trimmedText {
            liveTranslationRevision &+= 1
        }
        liveRecognitionText = trimmedText
        guard let session = appState.translationSession else { return }
        if !isTranslatingPartial {
            translateLatestPartial(session: session)
        } else {
            pendingTranslation = true
        }
    }

    private func requestEntryTranslation(entryID: UUID, sourceText: String) {
        entryTranslationTasks[entryID]?.cancel()
        guard let request = appState.beginEntryTranslation(entryID: entryID) else { return }

        let expectedSource = request.sourceText
        let requestID = request.requestID
        let runID = translationRunID
        let configRevision = appState.translationConfigurationRevision
        let translationMode = appState.translationMode
        let sourceLanguage = AppState.localizedDisplayName(for: appState.sourceLanguage,
                                                           in: Locale(identifier: "en"))
        let targetLanguage = AppState.localizedDisplayName(for: appState.targetLanguage,
                                                           in: Locale(identifier: "en"))
        let existingDraft = appState.transcriptEntries.first(where: { $0.id == entryID })?.translatedText ?? ""

        entryTranslationTasks[entryID] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if self.appState.transcriptEntries.first(where: { $0.id == entryID })?.translationRequestID == requestID {
                    self.entryTranslationTasks[entryID] = nil
                }
            }
            var appleDraft = existingDraft

            if let session = self.appState.translationSession {
                let startedAt = Date()
                if let response = try? await session.translate(sourceText),
                   !Task.isCancelled,
                   self.translationRunID == runID,
                   self.appState.translationConfigurationRevision == configRevision {
                    appleDraft = response.targetText
                    if self.appState.applyEntryTranslation(response.targetText,
                                                           entryID: entryID,
                                                           requestID: requestID,
                                                           expectedSource: expectedSource,
                                                           stage: .appleDraft) {
                        self.appState.lastTranslationMilliseconds = Int((Date().timeIntervalSince(startedAt) * 1_000).rounded())
                        self.appState.lastTranslationEngine = "Apple"
                    }
                }
            }

            guard translationMode == .hybrid,
                  !Task.isCancelled,
                  self.translationRunID == runID,
                   self.appState.translationConfigurationRevision == configRevision else { return }

            let context = self.appState.translationContext(before: entryID)
            do {
                let result = try await OllamaTranslationRefiner.shared.refine(
                    sourceText: sourceText,
                    appleDraft: appleDraft,
                    sourceLanguage: sourceLanguage,
                    targetLanguage: targetLanguage,
                    context: context
                )
                guard !Task.isCancelled,
                      self.translationRunID == runID,
                   self.appState.translationConfigurationRevision == configRevision else { return }

                if self.appState.applyEntryTranslation(result.translation,
                                                       entryID: entryID,
                                                       requestID: requestID,
                                                       expectedSource: expectedSource,
                                                       stage: .contextualAI) {
                    self.appState.lastTranslationMilliseconds = Int((result.duration * 1_000).rounded())
                    self.appState.lastTranslationEngine = result.model
                }
            } catch is CancellationError {
                return
            } catch {
                // Apple draft is intentionally retained when the Mini PC or model is unavailable.
                print("[SimulTrans] Context translation unavailable; kept Apple draft: \(error.localizedDescription)")
            }
        }
    }

    private func didRecognitionWindowChange(previousUpdate: RecognitionUpdate?,
                                            currentUpdate: RecognitionUpdate) -> Bool {
        didRecognitionTimelineReset(previousUpdate: previousUpdate, currentUpdate: currentUpdate)
            || didTimedSegmentAdvance(previousUpdate: previousUpdate, currentUpdate: currentUpdate)
    }

    private func didTimedSegmentAdvance(previousUpdate: RecognitionUpdate?,
                                        currentUpdate: RecognitionUpdate) -> Bool {
        guard let previousUpdate,
              let previousSegment = previousUpdate.segments.last,
              let currentSegment = currentUpdate.segments.first else { return false }

        let previousStart = previousUpdate.segments.first?.timestamp ?? 0
        let previousEnd = previousSegment.endTime
        let currentStart = currentSegment.timestamp

        guard previousEnd > 0, currentStart > 0 else { return false }
        return currentStart > previousStart + 0.2 && currentStart >= previousEnd - 0.12
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

    private func replaceLiveOriginalText(with text: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return }
        guard appState.currentOriginalText != trimmedText else { return }

        if !trimmedText.hasPrefix(appState.currentOriginalText) {
            appState.currentTranslatedText = ""
            translatedLiveSource = ""
        }
        appState.currentOriginalText = trimmedText
        liveDisplayRevision += 1
    }

    private func clearLiveEntry() {
        liveSegmentID = UUID()
        translatedLiveSource = ""
        isTranslatingPartial = false
        appState.currentOriginalText = ""
        appState.currentTranslatedText = ""
        liveRecognitionText = ""
        liveDisplayRevision = 0
        liveTranslationRevision &+= 1
        pendingTranslation = false
        activeLiveTranslationRevision = nil
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

    // MARK: - Overlay

    private func showOverlay() {
        if overlayPanel == nil {
            overlayPanel = OverlayPanel(contentRect: .zero)
            let view = OverlayContentView(
                onExport: { [weak self] in self?.exportTranscript() },
                onHide: { [weak self] in self?.hideOverlay() },
                onTranslationReady: { [weak self] in self?.translationSessionReady() }
            ).environment(appState)
            let hostingView = NSHostingView(rootView: AnyView(view))
            overlayPanel?.contentView = hostingView
            overlayPanel?.delegate = self
        }
        overlayPanel?.orderFrontRegardless()
        appState.overlayVisible = true
    }

    private func hideOverlay() {
        overlayPanel?.orderOut(nil)
        appState.overlayVisible = false
    }

    private func toggleOverlayVisibility() {
        if overlayPanel?.isVisible == true {
            hideOverlay()
        } else {
            showOverlay()
        }
    }
}
