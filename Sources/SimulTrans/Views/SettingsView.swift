import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: Tab = .general

    enum Tab: String, CaseIterable, Identifiable {
        case general
        case recognition
        case languages
        case overlay
        case advanced

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .general: return "slider.horizontal.3"
            case .recognition: return "waveform"
            case .languages: return "character.bubble"
            case .overlay: return "rectangle.on.rectangle"
            case .advanced: return "gearshape.2"
            }
        }

        var localizationKey: String {
            switch self {
            case .general: return "General"
            case .recognition: return "Audio & Recognition"
            case .languages: return "Translation"
            case .overlay: return "Overlay"
            case .advanced: return "Advanced"
            }
        }
    }

    var body: some View {
        @Bindable var appState = appState

        HStack(spacing: 0) {
            sidebar
                .frame(width: 206)

            Rectangle()
                .fill(STTheme.rule)
                .frame(width: 1)

            content(appState: appState)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 760, minHeight: 580)
        .background(STWindowBackdrop())
        .preferredColorScheme(appState.appearancePreference.colorScheme)
        .environment(\.locale, appState.appInterfaceLocale)
        .onChange(of: appState.sourceLanguage) { appState.updateTranslationConfig() }
        .onChange(of: appState.targetLanguage) { appState.updateTranslationConfig() }
        .onChange(of: appState.appearancePreference) { _, newValue in
            NSApp.appearance = newValue.nsAppearance
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                STBrandMark(compact: true)
                Text("Settings", bundle: .module)
                    .font(STTheme.bodyFont(size: 12, weight: .semibold))
                    .foregroundStyle(STTheme.secondaryLabel)
            }
            .padding(.horizontal, 20)
            .padding(.top, 28)
            .padding(.bottom, 30)

            VStack(spacing: 6) {
                ForEach(Tab.allCases) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedTab = tab
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: tab.systemImage)
                                .font(.system(size: 15, weight: .medium))
                                .frame(width: 20)
                                .foregroundStyle(tab == selectedTab ? STTheme.accent : STTheme.secondaryLabel)
                            Text(appState.localizedAppString(tab.localizationKey))
                                .font(STTheme.bodyFont(size: 13, weight: tab == selectedTab ? .semibold : .medium))
                                .foregroundStyle(tab == selectedTab ? STTheme.primaryLabel : STTheme.secondaryLabel)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 11)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background {
                            if tab == selectedTab {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(STTheme.accentSoft)
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(STTheme.accent.opacity(0.14), lineWidth: 1)
                                    }
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(tab == selectedTab ? .isSelected : [])
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            Text("v\(versionString)")
                .font(STTheme.bodyFont(size: 11, weight: .medium))
                .foregroundStyle(STTheme.inkTertiary)
                .padding(.horizontal, 24)
                .padding(.bottom, 22)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.ultraThinMaterial)
    }

    // MARK: - Content

    @ViewBuilder
    private func content(appState: AppState) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                contentHeader(eyebrow: appState.localizedAppString(selectedTab.localizationKey),
                              title: titleForTab(selectedTab))

                VStack(spacing: 0) {
                    switch selectedTab {
                    case .general:
                        generalRows(appState: appState)
                    case .recognition:
                        recognitionRows(appState: appState)
                    case .languages:
                        languagesRows(appState: appState)
                    case .overlay:
                        overlayRows(appState: appState)
                    case .advanced:
                        advancedRows(appState: appState)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 6)
                .background(STGlassSurface(radius: 22))
            }
            .padding(.horizontal, 30)
            .padding(.top, 30)
            .padding(.bottom, 32)
            .frame(maxWidth: 900, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private func titleForTab(_ tab: Tab) -> String {
        switch tab {
        case .general:
            return appState.localizedAppString("App behavior and appearance")
        case .recognition:
            return appState.localizedAppString("Choose where speech recognition runs")
        case .languages:
            return appState.localizedAppString("Source and target languages")
        case .overlay:
            return appState.localizedAppString("Caption layout and readability")
        case .advanced:
            return appState.localizedAppString("Diagnostics and data path")
        }
    }

    private func contentHeader(eyebrow: String, title: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            STIconBadge(systemName: selectedTab.systemImage, size: 46)
            VStack(alignment: .leading, spacing: 6) {
                Text(eyebrow)
                    .font(STTheme.displayFont(size: 27, weight: .semibold))
                    .foregroundStyle(STTheme.primaryLabel)
                Text(title)
                    .font(STTheme.bodyFont(size: 13))
                    .foregroundStyle(STTheme.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - General

    @ViewBuilder
    private func generalRows(appState: AppState) -> some View {
        @Bindable var appState = appState

        SetRow(label: appState.localizedAppString("App Language")) {
            AppLanguagePicker(selection: $appState.appDisplayLanguage)
        }
        SetRow(label: appState.localizedAppString("Show menu bar icon")) {
            STSwitch(isOn: $appState.showMenuBarIcon)
        }
        SetRow(label: appState.localizedAppString("Theme")) {
            STSegmented(options: AppearancePreference.allCases.map { ($0, $0.label(in: appState.appInterfaceLocale)) },
                        selected: $appState.appearancePreference)
        }
    }

    // MARK: - Audio & Recognition

    @ViewBuilder
    private func recognitionRows(appState: AppState) -> some View {
        @Bindable var appState = appState

        SetRow(label: appState.localizedAppString("Audio source"),
               hint: appState.localizedAppString("Capture the whole Mac or use a microphone.")) {
            STSegmented(options: AppState.AudioSource.allCases.map {
                ($0, $0.localizedName(in: appState.appInterfaceLocale))
            }, selected: $appState.audioSource)
            .disabled(appState.isRunning)
        }

        SetRow(label: appState.localizedAppString("Recognition engine"),
               hint: appState.localizedAppString(appState.recognitionEngine.setupHint)) {
            STSegmented(options: RecognitionEngine.allCases.map { ($0, $0.shortLabel) },
                        selected: $appState.recognitionEngine)
                .disabled(appState.isRunning)
        }

        SetRow(label: appState.localizedAppString("Processing location"),
               hint: recognitionPrivacyDescription(appState.recognitionEngine)) {
            Text(recognitionLocation(appState.recognitionEngine))
                .font(STTheme.bodyFont(size: 11, weight: .medium))
                .foregroundStyle(STTheme.liveStatus)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(STTheme.liveStatus.opacity(0.10)))
        }
    }

    // MARK: - Languages

    @ViewBuilder
    private func languagesRows(appState: AppState) -> some View {
        @Bindable var appState = appState

        SetRow(label: appState.localizedAppString("Translation quality"),
               hint: appState.localizedAppString("Context AI shows an Apple draft first, then improves final subtitles on your Mini PC.")) {
            STSegmented(options: AppState.TranslationMode.allCases.map {
                ($0, appState.localizedAppString($0.localizationKey))
            }, selected: $appState.translationMode)
        }
        SetRow(label: appState.localizedAppString("Source language"),
               hint: appState.localizedAppString("What you expect to hear.")) {
            LanguagePicker(selection: $appState.sourceLanguage)
        }
        SetRow(label: appState.localizedAppString("Translate to"),
               hint: appState.localizedAppString("Apple Translation runs on-device when the language pair is downloaded.")) {
            LanguagePicker(selection: $appState.targetLanguage)
        }
    }

    // MARK: - Overlay

    @ViewBuilder
    private func overlayRows(appState: AppState) -> some View {
        @Bindable var appState = appState

        SetRow(label: appState.localizedAppString("Opacity"),
               hint: appState.localizedAppString("Background opacity of the floating overlay.")) {
            SliderControl(value: $appState.overlayOpacity, range: 0.35...1.0, step: 0.05)
        }
        SetRow(label: appState.localizedAppString("Caption layout"),
               hint: appState.localizedAppString("Choose translation only, bilingual captions or a full transcript.")) {
            STSegmented(options: AppState.OverlayLayoutMode.allCases.map {
                ($0, appState.localizedAppString($0.localizationKey))
            }, selected: $appState.overlayLayoutMode)
        }
        SetRow(label: String(format: appState.localizedAppString("Text size · %lld pt"),
                             locale: appState.appInterfaceLocale,
                             Int(appState.fontSize))) {
            SliderControl(value: Binding(get: { Double(appState.fontSize) },
                                         set: { appState.fontSize = CGFloat($0) }),
                          range: 18...48,
                          step: 1)
        }
    }

    // MARK: - Advanced

    @ViewBuilder
    private func advancedRows(appState: AppState) -> some View {
        @Bindable var appState = appState

        SetRow(label: appState.localizedAppString("Translation engine"),
               hint: appState.localizedAppString("Runs locally via Apple Translation.")) {
            Text("On-device", bundle: .module)
                .font(STTheme.bodyFont(size: 13, weight: .medium))
                .foregroundStyle(STTheme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(STTheme.accentSoft)
                        .overlay(Capsule().stroke(STTheme.accent.opacity(0.14), lineWidth: 1))
                )
        }

        SetRow(label: appState.localizedAppString("Show recognition diagnostics"),
               hint: appState.localizedAppString("Inspect raw and displayed text when recognition behaves unexpectedly.")) {
            STSwitch(isOn: $appState.debugPanelExpanded)
        }

        if appState.debugPanelExpanded {
            VStack(alignment: .leading, spacing: 10) {
                if let asr = appState.lastASRProcessingMilliseconds {
                    diagnosticBlock(title: appState.localizedAppString("Last ASR processing"),
                                    text: "\(asr) ms")
                }
                if let queue = appState.lastASRQueueMilliseconds {
                    diagnosticBlock(title: appState.localizedAppString("Last ASR queue"),
                                    text: "\(queue) ms")
                }
                if let translation = appState.lastTranslationMilliseconds {
                    diagnosticBlock(title: appState.localizedAppString("Last translation"),
                                    text: "\(appState.lastTranslationEngine ?? "—") · \(translation) ms")
                }
                diagnosticBlock(title: appState.localizedAppString("Raw recognizer text"),
                                text: appState.rawRecognitionText)
                diagnosticBlock(title: appState.localizedAppString("Effective text"),
                                text: appState.effectiveRecognitionText)
                diagnosticBlock(title: appState.localizedAppString("Displayed live text"),
                                text: appState.currentOriginalText)
                diagnosticBlock(title: appState.localizedAppString("Current translation"),
                                text: appState.currentTranslatedText)
            }
            .padding(16)
            .background(STGlassSurface(radius: 14))
            .padding(.vertical, 14)
        }
    }

    private func diagnosticBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(STTheme.bodyFont(size: 11, weight: .medium))
                .foregroundStyle(STTheme.inkTertiary)
            Text(text.isEmpty ? appState.localizedAppString("No data yet") : text)
                .font(STTheme.monoFont(size: 11, weight: .regular))
                .foregroundStyle(text.isEmpty ? STTheme.inkTertiary : STTheme.inkSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func recognitionLocation(_ engine: RecognitionEngine) -> String {
        switch engine {
        case .appleSpeech: return appState.localizedAppString("This Mac")
        case .whisperLargeV3Turbo: return appState.localizedAppString("This Mac · Local model")
        case .qwen3ASR1_7B: return appState.localizedAppString("Mini PC · Private tunnel")
        }
    }

    private func recognitionPrivacyDescription(_ engine: RecognitionEngine) -> String {
        switch engine {
        case .appleSpeech:
            return appState.localizedAppString("Speech recognition stays on this Mac.")
        case .whisperLargeV3Turbo:
            return appState.localizedAppString("Audio is processed by the local Whisper service on this Mac.")
        case .qwen3ASR1_7B:
            return appState.localizedAppString("Audio is sent through your private encrypted tunnel to the Mini PC, not to a cloud provider.")
        }
    }

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}

// MARK: - Reusable atoms

private struct SetRow<Control: View>: View {
    let label: String
    var hint: String? = nil
    @ViewBuilder var control: () -> Control

    private var description: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(STTheme.bodyFont(size: 13, weight: .semibold))
                .foregroundStyle(STTheme.ink)
            if let hint {
                Text(hint)
                    .font(STTheme.bodyFont(size: 12))
                    .foregroundStyle(STTheme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 22) {
                description.frame(minWidth: 160)
                control().fixedSize(horizontal: true, vertical: false)
            }
            VStack(alignment: .leading, spacing: 14) {
                description
                control()
            }
        }
        .padding(.vertical, 19)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(STTheme.rule.opacity(0.7))
                .frame(height: 1)
        }
    }
}

private struct STSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("", isOn: $isOn)
            .toggleStyle(.switch)
            .labelsHidden()
            .tint(STTheme.accent)
            .controlSize(.regular)
    }
}

private struct STSegmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selected: T

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, item in
                let (value, label) = item
                Button {
                    withAnimation(.easeInOut(duration: 0.16)) {
                        selected = value
                    }
                } label: {
                    Text(label)
                        .font(STTheme.bodyFont(size: 11, weight: value == selected ? .semibold : .medium))
                        .foregroundStyle(value == selected ? STTheme.accent : STTheme.inkSecondary)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 8)
                        .background {
                            if value == selected {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(STTheme.surfaceHighlight)
                                    .shadow(color: STTheme.shadow.opacity(0.4), radius: 3, x: 0, y: 1)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(value == selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(STTheme.rule.opacity(0.45))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(STTheme.glassBorder, lineWidth: 1)
                }
        }
    }
}

private struct LanguagePicker: View {
    @Environment(AppState.self) private var appState
    @Binding var selection: Locale.Language
    @State private var presented = false

    var body: some View {
        Button {
            presented.toggle()
        } label: {
            HStack(spacing: 0) {
                Text(AppState.localizedDisplayName(for: selection, in: appState.appInterfaceLocale))
                    .font(STTheme.bodyFont(size: 13, weight: .medium))
                    .foregroundStyle(STTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(minWidth: 148, alignment: .leading)

                Rectangle()
                    .fill(STTheme.ruleHard)
                    .frame(width: 1, height: 16)
                    .padding(.vertical, 7)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(STTheme.inkTertiary)
                    .frame(width: 30, height: 32)
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(STTheme.surfaceHighlight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(STTheme.glassBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $presented, arrowEdge: .top) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(AppState.supportedLanguages) { language in
                        Button {
                            selection = language.locale
                            presented = false
                        } label: {
                            HStack {
                                Text(AppState.localizedDisplayName(for: language.locale, in: appState.appInterfaceLocale))
                                    .font(STTheme.bodyFont(size: 13, weight: .medium))
                                    .foregroundStyle(STTheme.ink)
                                Spacer()
                                if matchedSupportedLanguage(for: selection)?.id == language.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(STTheme.accent)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.clear)
                        }
                        .buttonStyle(.plain)

                        if language.id != AppState.supportedLanguages.last?.id {
                            Rectangle()
                                .fill(STTheme.rule)
                                .frame(height: 1)
                        }
                    }
                }
            }
            .frame(width: 240, height: 320)
            .padding(8)
            .background(.regularMaterial)
        }
    }

    private func matchedSupportedLanguage(for selection: Locale.Language) -> AppState.SupportedLanguage? {
        AppState.supportedLanguage(for: selection)
    }
}

private struct AppLanguagePicker: View {
    @Environment(AppState.self) private var appState
    @Binding var selection: AppState.AppDisplayLanguage
    @State private var presented = false

    var body: some View {
        Button {
            presented.toggle()
        } label: {
            HStack(spacing: 0) {
                Text(appState.localizedAppDisplayLanguageName(selection))
                    .font(STTheme.bodyFont(size: 13, weight: .medium))
                    .foregroundStyle(STTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .frame(minWidth: 148, alignment: .leading)

                Rectangle()
                    .fill(STTheme.ruleHard)
                    .frame(width: 1, height: 16)
                    .padding(.vertical, 7)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(STTheme.inkTertiary)
                    .frame(width: 30, height: 32)
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(STTheme.surfaceHighlight)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(STTheme.glassBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $presented, arrowEdge: .top) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(AppState.AppDisplayLanguage.allCases) { option in
                        Button {
                            selection = option
                            presented = false
                        } label: {
                            HStack {
                                Text(appState.localizedAppDisplayLanguageName(option))
                                    .font(STTheme.bodyFont(size: 13, weight: .medium))
                                    .foregroundStyle(STTheme.ink)
                                Spacer()
                                if selection == option {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(STTheme.accent)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.clear)
                        }
                        .buttonStyle(.plain)

                        if option != AppState.AppDisplayLanguage.allCases.last {
                            Rectangle()
                                .fill(STTheme.rule)
                                .frame(height: 1)
                        }
                    }
                }
            }
            .frame(width: 240, height: 176)
            .padding(8)
            .background(.regularMaterial)
        }
    }
}

private struct SliderControl: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        STSmoothSlider(value: $value, range: range, step: step)
            .tint(STTheme.accent)
            .controlSize(.regular)
            .frame(width: 170)
    }
}

private struct HotkeyChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(STTheme.monoFont(size: 11))
            .tracking(1)
            .foregroundStyle(STTheme.ink)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(STTheme.glassBorder, lineWidth: 1)
            )
    }
}
