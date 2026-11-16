import AppKit
import SwiftUI

/// The primary product surface. Idle mode is a focused setup flow; live mode
/// becomes a session monitor instead of leaving users inside a settings form.
struct ControlWindowView: View {
    @Bindable var appState: AppState
    var onStart: () -> Void
    var onStop: () -> Void
    var onExport: () -> Void
    var onClear: () -> Void
    var onToggleOverlay: () -> Void
    var onOpenSettings: () -> Void

    @State private var sourceLanguageMenuPresented = false
    @State private var targetLanguageMenuPresented = false
    @State private var showingClearConfirmation = false

    var body: some View {
        ZStack {
            STWindowBackdrop()

            VStack(spacing: 0) {
                topBar

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        if let error = appState.errorMessage {
                            recoveryCard(error)
                        }

                        if appState.isRunning {
                            liveSessionCard
                        } else {
                            quickSetupCard
                        }

                        overlayCard

                        if !appState.transcriptEntries.isEmpty {
                            recentResultCard
                        } else if !appState.isRunning {
                            permissionNote
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 18)
                    .padding(.bottom, 22)
                }

                actionBar
            }
        }
        .frame(minWidth: STTheme.controlWindowMinSize.width,
               minHeight: STTheme.controlWindowMinSize.height)
        .preferredColorScheme(appState.appearancePreference.colorScheme)
        .environment(\.locale, appState.appInterfaceLocale)
        .confirmationDialog(appState.localizedAppString("Clear this session?"),
                            isPresented: $showingClearConfirmation) {
            Button(appState.localizedAppString("Clear session"), role: .destructive, action: onClear)
            Button(appState.localizedAppString("Cancel"), role: .cancel) {}
        } message: {
            Text(appState.localizedAppString("This removes the current transcript. Export it first if you want to keep a copy."))
        }
        .onChange(of: appState.appearancePreference) { _, newValue in
            NSApp.appearance = newValue.nsAppearance
        }
    }

    // MARK: - Product header

    private var topBar: some View {
        HStack(spacing: 12) {
            STBrandMark(compact: true)

            Spacer(minLength: 8)

            sessionStatusPill

            Button(action: onOpenSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(STButtonStyle(.quiet, compact: true))
            .help(appState.localizedAppString("Settings"))
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) {
            Rectangle().fill(STTheme.glassBorder).frame(height: 1)
        }
    }

    private var sessionStatusPill: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 6, height: 6)

            if appState.isRunning, appState.sessionStartedAt != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("\(statusLabel) · \(AppState.formatElapsed(from: appState.sessionStartedAt, now: context.date))")
                        .font(.system(size: 10, weight: .medium))
                        .monospacedDigit()
                }
            } else {
                Text(statusLabel)
                    .font(.system(size: 10, weight: .medium))
            }
        }
        .foregroundStyle(STTheme.secondaryLabel)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Capsule().fill(statusColor.opacity(0.08)))
        .overlay(Capsule().stroke(statusColor.opacity(0.14), lineWidth: 1))
    }

    // MARK: - Idle setup

    private var quickSetupCard: some View {
        STCard {
            VStack(alignment: .leading, spacing: 20) {
                cardHeading(icon: "slider.horizontal.3",
                            title: appState.localizedAppString("New live session"),
                            detail: appState.localizedAppString("Choose the source, recognition engine and language route."))

                controlGroup(title: appState.localizedAppString("Audio source")) {
                    segmentedAudioSource
                }

                controlGroup(title: appState.localizedAppString("Recognition")) {
                    engineSelector
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(appState.localizedAppString("Language route"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(STTheme.secondaryLabel)

                    HStack(spacing: 8) {
                        languageDropdown(selection: appState.sourceLanguage,
                                         isPresented: $sourceLanguageMenuPresented) { language in
                            appState.sourceLanguage = language.locale
                        }

                        Button(action: swapLanguages) {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(STTheme.accent)
                                .frame(width: 30, height: 38)
                        }
                        .buttonStyle(STControlInteractionStyle())
                        .help(appState.localizedAppString("Swap languages"))

                        languageDropdown(selection: appState.targetLanguage,
                                         isPresented: $targetLanguageMenuPresented) { language in
                            appState.targetLanguage = language.locale
                        }
                    }
                }
            }
        }
    }

    private var segmentedAudioSource: some View {
        HStack(spacing: 6) {
            ForEach(AppState.AudioSource.allCases, id: \.self) { source in
                selectionButton(title: source.localizedName(in: appState.appInterfaceLocale),
                                icon: source == .system ? "speaker.wave.2" : "mic",
                                selected: source == appState.audioSource) {
                    appState.audioSource = source
                }
            }
        }
    }

    private var engineSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(RecognitionEngine.allCases) { engine in
                    selectionButton(title: engine.shortLabel,
                                    icon: engineIcon(engine),
                                    selected: engine == appState.recognitionEngine) {
                        appState.recognitionEngine = engine
                    }
                    .help(engine.displayName)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: appState.recognitionEngine == .qwen3ASR1_7B ? "desktopcomputer" : "laptopcomputer")
                    .foregroundStyle(STTheme.accent.opacity(0.75))
                Text(engineLocationLabel)
                    .fixedSize()
                Text("·")
                Text(appState.localizedAppString(appState.recognitionEngine.setupHint))
                    .lineLimit(2)
            }
            .font(.system(size: 10))
            .foregroundStyle(STTheme.tertiaryLabel)
            .padding(.horizontal, 2)
        }
    }

    // MARK: - Live session

    private var liveSessionCard: some View {
        STCard(accented: true) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    cardHeading(icon: "waveform",
                                title: appState.localizedAppString("Live session"),
                                detail: compactRouteLabel)

                    Spacer()

                    Text(engineLocationLabel)
                        .font(STTheme.monoFont(size: 10))
                        .foregroundStyle(STTheme.liveStatus)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(STTheme.liveStatus.opacity(0.12)))
                }

                liveTextPreview

                HStack(spacing: 8) {
                    metricChip(icon: "waveform", value: phaseDetail)
                    metricChip(icon: "text.bubble", value: "\(appState.transcriptEntries.count)")
                    metricChip(icon: "rectangle.on.rectangle", value: appState.overlayVisible
                               ? appState.localizedAppString("Visible")
                               : appState.localizedAppString("Hidden"))
                }

                if appState.lastASRProcessingMilliseconds != nil || appState.lastTranslationMilliseconds != nil {
                    HStack(spacing: 8) {
                        if let milliseconds = appState.lastASRProcessingMilliseconds {
                            metricChip(icon: "timer",
                                       value: "ASR \(milliseconds) ms")
                        }
                        if let milliseconds = appState.lastTranslationMilliseconds {
                            metricChip(icon: "sparkles",
                                       value: "\(appState.lastTranslationEngine ?? "AI") \(milliseconds) ms")
                        }
                    }
                }
            }
        }
    }

    private var liveTextPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            if appState.currentOriginalText.isEmpty {
                HStack(spacing: 10) {
                    ListeningBars(active: appState.sessionPhase != .starting)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.sessionPhase == .starting
                             ? appState.localizedAppString("Waking the recognition engine…")
                             : appState.localizedAppString("Listening for speech…"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(STTheme.primaryLabel)
                        Text(appState.localizedAppString("The first recognized phrase will appear here."))
                            .font(.system(size: 12))
                            .foregroundStyle(STTheme.tertiaryLabel)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            } else {
                Text(appState.currentOriginalText)
                    .font(.system(size: 13))
                    .foregroundStyle(STTheme.secondaryLabel)
                    .lineLimit(3)

                Text(appState.currentTranslatedText.isEmpty
                     ? appState.localizedAppString("Translating…")
                     : appState.currentTranslatedText)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(appState.currentTranslatedText.isEmpty ? STTheme.tertiaryLabel : STTheme.primaryLabel)
                    .lineLimit(4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(STGlassSurface(radius: 16))
    }

    // MARK: - Overlay controls

    private var overlayCard: some View {
        STCard {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 10) {
                    cardHeading(icon: "captions.bubble",
                                title: appState.localizedAppString("Live captions"),
                                detail: appState.localizedAppString("A focused overlay designed for video and meetings."))
                    Spacer(minLength: 0)
                    Button(action: onToggleOverlay) {
                        Label(appState.overlayVisible
                              ? appState.localizedAppString("Hide")
                              : appState.localizedAppString("Show"),
                              systemImage: appState.overlayVisible ? "eye.slash" : "eye")
                            .font(.system(size: 11, weight: .semibold))
                            .fixedSize()
                    }
                    .buttonStyle(STButtonStyle(.secondary, compact: true))
                }

                overlayModeSelector

                HStack(spacing: 22) {
                    sliderRow(icon: "circle.lefthalf.filled",
                              valueText: "\(Int(appState.overlayOpacity * 100))%") {
                        STSmoothSlider(value: $appState.overlayOpacity, range: 0.35...1.0, step: 0.05)
                    }

                    sliderRow(icon: "textformat.size",
                              valueText: "\(Int(appState.fontSize)) pt") {
                        STSmoothSlider(value: Binding(get: { Double(appState.fontSize) },
                                              set: { appState.fontSize = CGFloat($0) }),
                               range: 18...48,
                               step: 1)
                    }
                }

                if !appState.isRunning {
                    overlayPreview
                }
            }
        }
    }

    private var overlayModeSelector: some View {
        HStack(spacing: 6) {
            ForEach(AppState.OverlayLayoutMode.allCases) { mode in
                Button {
                    appState.overlayLayoutMode = mode
                } label: {
                    Text(appState.localizedAppString(mode.localizationKey))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(mode == appState.overlayLayoutMode ? STTheme.accent : STTheme.secondaryLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            if mode == appState.overlayLayoutMode {
                                STGlassSurface(radius: 10, accented: true)
                            }
                        }
                }
                .buttonStyle(STControlInteractionStyle())
            }
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 14).fill(STTheme.controlBackground.opacity(0.72)))
    }

    private var overlayPreview: some View {
        VStack(alignment: .leading, spacing: 5) {
            if appState.overlayLayoutMode != .subtitles {
                Text(appState.localizedAppString("Spoken words appear here"))
                    .font(.system(size: 11))
                    .foregroundStyle(STTheme.overlaySecondary)
            }
            Text(appState.localizedAppString("Translation appears here"))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(STTheme.overlayPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(STTheme.overlayBackground.opacity(appState.overlayOpacity)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.10), lineWidth: 1))
    }

    private var recentResultCard: some View {
        STCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(appState.localizedAppString("Latest result"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(STTheme.primaryLabel)
                    Spacer()
                    Text("\(appState.transcriptEntries.count) \(appState.localizedAppString("entries"))")
                        .font(STTheme.monoFont(size: 10))
                        .foregroundStyle(STTheme.tertiaryLabel)
                }

                if let last = appState.transcriptEntries.last {
                    Text(last.translatedText ?? last.originalText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(STTheme.secondaryLabel)
                        .lineLimit(3)

                    Button(action: copyLatestResult) {
                        Label(appState.localizedAppString("Copy latest translation"), systemImage: "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(STButtonStyle(.quiet, compact: true))
                    .foregroundStyle(STTheme.accent)
                }
            }
        }
    }

    // MARK: - Recovery and actions

    private func recoveryCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(STTheme.danger)
                VStack(alignment: .leading, spacing: 3) {
                    Text(appState.localizedAppString("Needs attention"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(STTheme.primaryLabel)
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundStyle(STTheme.secondaryLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                if !appState.isRunning {
                    Button(appState.localizedAppString("Try again"), action: onStart)
                        .buttonStyle(STButtonStyle(.primary, compact: true))
                }
                if appState.recognitionEngine == .qwen3ASR1_7B && !appState.isRunning {
                    Button(appState.localizedAppString("Use Apple instead")) {
                        appState.recognitionEngine = .appleSpeech
                        appState.errorMessage = nil
                    }
                    .buttonStyle(STButtonStyle(.secondary, compact: true))
                }
                Button(appState.localizedAppString("Dismiss")) {
                    appState.errorMessage = nil
                }
                .buttonStyle(STButtonStyle(.quiet, compact: true))
            }
        }
        .padding(18)
        .background(STGlassSurface(radius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(STTheme.danger.opacity(0.24), lineWidth: 1))
    }

    private var permissionNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: appState.audioSource == .system ? "rectangle.inset.filled.and.person.filled" : "mic.badge.plus")
                .foregroundStyle(STTheme.tertiaryLabel)
            Text(appState.audioSource == .system
                 ? appState.localizedAppString("Screen Recording permission is required the first time you translate system audio.")
                 : appState.localizedAppString("Microphone permission is required the first time you translate microphone input."))
                .font(.system(size: 12))
                .foregroundStyle(STTheme.tertiaryLabel)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 4)
    }

    private var actionBar: some View {
        VStack(spacing: 10) {
            Button(action: appState.isRunning ? onStop : onStart) {
                HStack(spacing: 9) {
                    if appState.sessionPhase == .starting {
                        ProgressView().controlSize(.small).tint(.white)
                    } else {
                        Image(systemName: appState.isRunning ? "stop.fill" : "play.fill")
                            .font(.system(size: 11, weight: .bold))
                    }
                    Text(primaryActionLabel)
                        .font(.system(size: 14, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 30)
            }
            .buttonStyle(STButtonStyle(appState.isRunning ? .destructive : .primary))

            HStack(spacing: 10) {
                Button(action: onToggleOverlay) {
                    Label(appState.overlayVisible
                          ? appState.localizedAppString("Hide captions")
                          : appState.localizedAppString("Show captions"),
                          systemImage: appState.overlayVisible ? "eye.slash" : "eye")
                }
                .buttonStyle(STButtonStyle(.quiet, compact: true))

                Spacer()

                Menu {
                    Button(appState.localizedAppString("Export transcript"), action: onExport)
                        .disabled(appState.transcriptEntries.isEmpty)
                    Button(appState.localizedAppString("Clear session"), role: .destructive) {
                        showingClearConfirmation = true
                    }
                    .disabled(appState.transcriptEntries.isEmpty && appState.currentOriginalText.isEmpty)
                    Divider()
                    Button(appState.localizedAppString("Settings"), action: onOpenSettings)
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(STTheme.secondaryLabel)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(STTheme.glassBorder).frame(height: 1)
        }
    }

    // MARK: - Reusable controls and helpers

    private func cardHeading(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 11) {
            STIconBadge(systemName: icon, size: 34)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(STTheme.displayFont(size: 15, weight: .semibold))
                    .foregroundStyle(STTheme.primaryLabel)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(STTheme.tertiaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }
            .padding(.top, 1)
        }
    }

    private func controlGroup<Content: View>(title: String,
                                             @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(STTheme.secondaryLabel)
            content()
        }
    }

    private func selectionButton(title: String,
                                 icon: String,
                                 selected: Bool,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 11, weight: .medium))
                Text(title).lineLimit(1).minimumScaleFactor(0.8)
            }
            .font(.system(size: 12, weight: selected ? .semibold : .medium))
            .foregroundStyle(selected ? STTheme.accent : STTheme.secondaryLabel)
            .frame(maxWidth: .infinity)
            .frame(height: 38)
            .background {
                if selected {
                    STGlassSurface(radius: 12, accented: true)
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(STTheme.controlBackground.opacity(0.72))
                }
            }
        }
        .buttonStyle(STControlInteractionStyle())
    }

    private func languageDropdown(selection: Locale.Language,
                                  isPresented: Binding<Bool>,
                                  onSelect: @escaping (AppState.SupportedLanguage) -> Void) -> some View {
        Button { isPresented.wrappedValue.toggle() } label: {
            HStack(spacing: 6) {
                Text(languageName(for: selection))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(STTheme.primaryLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Spacer(minLength: 2)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(STTheme.tertiaryLabel)
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(STGlassSurface(radius: 12))
        }
        .buttonStyle(STControlInteractionStyle())
        .popover(isPresented: isPresented, arrowEdge: .top) {
            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(AppState.supportedLanguages) { language in
                        Button {
                            onSelect(language)
                            isPresented.wrappedValue = false
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(language.nativeName)
                                        .font(.system(size: 13, weight: .medium))
                                    if language.nativeName != language.name {
                                        Text(language.name)
                                            .font(.system(size: 10))
                                            .foregroundStyle(STTheme.tertiaryLabel)
                                    }
                                }
                                Spacer()
                                if language.id == matchedSupportedLanguage(for: selection)?.id {
                                    Image(systemName: "checkmark").foregroundStyle(STTheme.accent)
                                }
                            }
                            .foregroundStyle(STTheme.primaryLabel)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(STControlInteractionStyle())
                        Divider().opacity(0.35)
                    }
                }
            }
            .frame(width: 270, height: 360)
            .padding(8)
            .background(STTheme.cardBackground)
        }
    }

    private func sliderRow<SliderContent: View>(icon: String,
                                                valueText: String,
                                                @ViewBuilder slider: () -> SliderContent) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: icon)
                Spacer()
                Text(valueText).font(STTheme.monoFont(size: 10))
            }
            .foregroundStyle(STTheme.tertiaryLabel)
            slider().controlSize(.small).tint(STTheme.accent)
        }
        .frame(maxWidth: .infinity)
    }

    private func metricChip(icon: String, value: String) -> some View {
        Label(value, systemImage: icon)
            .font(STTheme.monoFont(size: 9))
            .foregroundStyle(STTheme.secondaryLabel)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Capsule().fill(STTheme.controlBackground))
    }

    private func swapLanguages() {
        guard !appState.isRunning else { return }
        let source = appState.sourceLanguage
        appState.sourceLanguage = appState.targetLanguage
        appState.targetLanguage = source
    }

    private func copyLatestResult() {
        guard let entry = appState.transcriptEntries.last else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.translatedText ?? entry.originalText, forType: .string)
    }

    private func matchedSupportedLanguage(for selection: Locale.Language) -> AppState.SupportedLanguage? {
        AppState.supportedLanguage(for: selection)
    }

    private func languageName(for selection: Locale.Language) -> String {
        AppState.localizedDisplayName(for: selection, in: appState.appInterfaceLocale)
    }

    private func languageCode(for selection: Locale.Language) -> String {
        let id = selection.minimalIdentifier.lowercased()
        if id.hasPrefix("zh") { return "ZH" }
        if id.hasPrefix("ja") { return "JA" }
        if id.hasPrefix("ko") { return "KO" }
        if id.hasPrefix("en") { return "EN" }
        if id.hasPrefix("pt") { return "PT" }
        if id.hasPrefix("es") { return "ES" }
        if id.hasPrefix("fr") { return "FR" }
        if id.hasPrefix("de") { return "DE" }
        return selection.minimalIdentifier.prefix(2).uppercased()
    }

    private func engineIcon(_ engine: RecognitionEngine) -> String {
        switch engine {
        case .appleSpeech: return "apple.logo"
        case .whisperLargeV3Turbo: return "waveform.badge.mic"
        case .qwen3ASR1_7B: return "desktopcomputer"
        }
    }

    private var engineLocationLabel: String {
        switch appState.recognitionEngine {
        case .appleSpeech: return appState.localizedAppString("Apple · This Mac")
        case .whisperLargeV3Turbo: return appState.localizedAppString("Whisper · This Mac")
        case .qwen3ASR1_7B: return appState.localizedAppString("Qwen · Mini PC")
        }
    }

    private var compactRouteLabel: String {
        "\(appState.audioSource.localizedName(in: appState.appInterfaceLocale)) · \(appState.recognitionEngine.shortLabel) · \(languageCode(for: appState.sourceLanguage)) → \(languageCode(for: appState.targetLanguage))"
    }

    private var phaseDetail: String {
        switch appState.sessionPhase {
        case .starting: return appState.localizedAppString("Starting")
        case .transcribing: return appState.localizedAppString("Transcribing")
        case .listening: return appState.localizedAppString("Listening")
        case .failed: return appState.localizedAppString("Needs attention")
        case .idle: return appState.localizedAppString("Ready")
        }
    }

    private var statusLabel: String {
        switch appState.sessionPhase {
        case .starting: return appState.localizedAppString("Starting")
        case .transcribing: return appState.localizedAppString("Live")
        case .listening: return appState.localizedAppString("Listening")
        case .failed: return appState.localizedAppString("Attention")
        case .idle: return appState.localizedAppString("Ready")
        }
    }

    private var statusColor: Color {
        switch appState.sessionPhase {
        case .starting: return STTheme.accent
        case .transcribing, .listening: return STTheme.liveStatus
        case .failed: return STTheme.danger
        case .idle: return STTheme.tertiaryLabel
        }
    }

    private var primaryActionLabel: String {
        if appState.sessionPhase == .starting { return appState.localizedAppString("Cancel startup") }
        return appState.isRunning
            ? appState.localizedAppString("Stop translation")
            : appState.localizedAppString("Start translation")
    }
}

private struct STCard<Content: View>: View {
    var accented: Bool = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(STGlassSurface(radius: 20, accented: accented))
    }
}

private struct ListeningBars: View {
    let active: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<9, id: \.self) { index in
                Capsule()
                    .fill(active ? STTheme.liveStatus : STTheme.tertiaryLabel)
                    .frame(width: 3, height: heights[index])
            }
        }
        .frame(width: 42, height: 34)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 12).fill(STTheme.liveStatus.opacity(active ? 0.10 : 0.05)))
    }

    private let heights: [CGFloat] = [8, 17, 12, 25, 19, 29, 14, 22, 10]
}

/// Keeps segmented controls and language pickers responsive without changing
/// their layout or competing with their selected state.
private struct STControlInteractionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        InteractionBody(configuration: configuration)
    }

    private struct InteractionBody: View {
        let configuration: ButtonStyle.Configuration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .contentShape(RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(STTheme.accent.opacity(configuration.isPressed ? 0.12 : (isHovered ? 0.06 : 0)))
                        .allowsHitTesting(false)
                }
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
                .opacity(isEnabled ? 1 : 0.45)
                .onHover { isHovered = $0 }
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovered)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
        }
    }
}
