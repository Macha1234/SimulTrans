import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: Tab = .general

    enum Tab: String, CaseIterable, Identifiable {
        case general
        case languages
        case overlay
        case hotkeys
        case export
        case advanced

        var id: String { rawValue }

        var localizationKey: String {
            switch self {
            case .general: return "General"
            case .languages: return "Languages"
            case .overlay: return "Overlay"
            case .hotkeys: return "Hotkeys"
            case .export: return "Export"
            case .advanced: return "Advanced"
            }
        }
    }

    var body: some View {
        @Bindable var appState = appState

        HStack(spacing: 0) {
            sidebar
                .frame(width: 168)

            Rectangle()
                .fill(STTheme.rule)
                .frame(width: 1)

            content(appState: appState)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(STTheme.bg)
        }
        .frame(width: STTheme.settingsWindowSize.width,
               height: STTheme.settingsWindowSize.height)
        .background(STTheme.bg)
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
            Text("Settings", bundle: .module)
                .font(STTheme.displayFont(size: 22, weight: .medium))
                .tracking(-0.6)
                .foregroundStyle(STTheme.ink)
                .padding(.horizontal, 16)
                .padding(.top, 22)
                .padding(.bottom, 18)

            ForEach(Tab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(appState.localizedAppString(tab.localizationKey))
                        .font(STTheme.bodyFont(size: 13, weight: tab == selectedTab ? .medium : .regular))
                        .foregroundStyle(tab == selectedTab ? STTheme.onAccent : STTheme.inkSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(tab == selectedTab ? STTheme.ink : Color.clear)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 1)
            }

            Spacer()

            Text("v\(versionString)")
                .font(STTheme.monoFont(size: 10))
                .tracking(1)
                .foregroundStyle(STTheme.inkTertiary)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(STTheme.panel)
    }

    // MARK: - Content

    @ViewBuilder
    private func content(appState: AppState) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                contentHeader(eyebrow: appState.localizedAppString(selectedTab.localizationKey),
                              title: titleForTab(selectedTab))

                switch selectedTab {
                case .general:
                    generalRows(appState: appState)
                case .languages:
                    languagesRows(appState: appState)
                case .overlay:
                    overlayRows(appState: appState)
                case .hotkeys:
                    hotkeysRows()
                case .export:
                    exportRows()
                case .advanced:
                    advancedRows(appState: appState)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 30)
        }
    }

    private func titleForTab(_ tab: Tab) -> String {
        switch tab {
        case .general:
            return appState.localizedAppString("How SimulTrans behaves.")
        case .languages:
            return appState.localizedAppString("Source and target.")
        case .overlay:
            return appState.localizedAppString("How the floating window looks.")
        case .hotkeys:
            return appState.localizedAppString("Keyboard shortcuts.")
        case .export:
            return appState.localizedAppString("Saving transcripts.")
        case .advanced:
            return appState.localizedAppString("Diagnostics and engine.")
        }
    }

    private func contentHeader(eyebrow: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(eyebrow)
                .font(STTheme.monoFont(size: 10))
                .tracking(2)
                .foregroundStyle(STTheme.accent)
                .textCase(.uppercase)

            Text(title)
                .font(STTheme.displayFont(size: 28, weight: .medium))
                .tracking(-0.8)
                .foregroundStyle(STTheme.ink)
        }
        .padding(.bottom, 4)
    }

    // MARK: - General

    @ViewBuilder
    private func generalRows(appState: AppState) -> some View {
        @Bindable var appState = appState

        SetRow(label: appState.localizedAppString("App Language")) {
            AppLanguagePicker(selection: $appState.appDisplayLanguage)
        }
        SetRow(label: appState.localizedAppString("Launch at login")) {
            STSwitch(isOn: $appState.launchAtLogin)
        }
        SetRow(label: appState.localizedAppString("Show menu bar icon")) {
            STSwitch(isOn: $appState.showMenuBarIcon)
        }
        SetRow(label: appState.localizedAppString("Hide dock icon"),
               hint: appState.localizedAppString("Run as a pure menu bar app (takes effect on next launch).")) {
            STSwitch(isOn: $appState.hideDockIcon)
        }
        SetRow(label: appState.localizedAppString("Dim overlay when silent"),
               hint: appState.localizedAppString("Fades the overlay to ~30% opacity after 10s of silence.")) {
            STSwitch(isOn: $appState.dimOverlayWhenSilent)
        }
        SetRow(label: appState.localizedAppString("Theme")) {
            STSegmented(options: AppearancePreference.allCases.map { ($0, $0.label(in: appState.appInterfaceLocale)) },
                        selected: $appState.appearancePreference)
        }
    }

    // MARK: - Languages

    @ViewBuilder
    private func languagesRows(appState: AppState) -> some View {
        @Bindable var appState = appState

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
            SliderControl(value: $appState.overlayOpacity, range: 0.3...1.0, step: 0.05)
        }
        SetRow(label: String(format: appState.localizedAppString("Text size · %lld pt"),
                             locale: appState.appInterfaceLocale,
                             Int(appState.fontSize))) {
            SliderControl(value: Binding(get: { Double(appState.fontSize) },
                                         set: { appState.fontSize = CGFloat($0) }),
                          range: 12...26,
                          step: 1)
        }
    }

    // MARK: - Hotkeys / Export placeholders

    @ViewBuilder
    private func hotkeysRows() -> some View {
        SetRow(label: appState.localizedAppString("Toggle overlay"),
               hint: appState.localizedAppString("Coming soon — global shortcut to show / hide the floating window.")) {
            HotkeyChip(text: "⌘⇧T")
        }
        SetRow(label: appState.localizedAppString("Start / stop translation"),
               hint: appState.localizedAppString("Coming soon.")) {
            HotkeyChip(text: "⌘⇧Space")
        }
    }

    @ViewBuilder
    private func exportRows() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SetRow(label: appState.localizedAppString("Default format"),
                   hint: appState.localizedAppString("Plain text with timestamp + source + translation.")) {
                Text("TXT")
                    .font(STTheme.monoFont(size: 11))
                    .tracking(1.5)
                    .foregroundStyle(STTheme.ink)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(STTheme.ruleHard, lineWidth: 1)
                    )
            }
            SetRow(label: appState.localizedAppString("Open exported files"),
                   hint: appState.localizedAppString("Reveals each export in Finder after saving.")) {
                STSwitch(isOn: .constant(true))
                    .opacity(0.6)
            }
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
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(STTheme.ruleHard, lineWidth: 1)
                )
        }

        SetRow(label: appState.localizedAppString("Show debug recognition panel"),
               hint: appState.localizedAppString("Surface raw / effective / displayed text in the control window for tuning.")) {
            STSwitch(isOn: $appState.debugPanelExpanded)
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

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(STTheme.bodyFont(size: 14, weight: .medium))
                    .foregroundStyle(STTheme.ink)

                if let hint {
                    Text(hint)
                        .font(STTheme.bodyFont(size: 12))
                        .foregroundStyle(STTheme.inkTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 16)

            control()
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(STTheme.rule)
                .frame(height: 1)
        }
    }
}

private struct STSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? STTheme.accent : STTheme.rule)
                    .frame(width: 36, height: 20)

                Circle()
                    .fill(STTheme.onAccent)
                    .frame(width: 16, height: 16)
                    .padding(2)
                    .shadow(color: STTheme.shadow, radius: 1, x: 0, y: 0.5)
            }
            .animation(.easeOut(duration: 0.18), value: isOn)
        }
        .buttonStyle(.plain)
    }
}

private struct STSegmented<T: Hashable>: View {
    let options: [(T, String)]
    @Binding var selected: T

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, item in
                let (value, label) = item
                Button {
                    selected = value
                } label: {
                    Text(label)
                        .font(STTheme.monoFont(size: 11))
                        .tracking(1)
                        .foregroundStyle(value == selected ? STTheme.onAccent : STTheme.inkSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(value == selected ? STTheme.ink : Color.clear)
                }
                .buttonStyle(.plain)

                if index != options.count - 1 {
                    Rectangle()
                        .fill(STTheme.ruleHard)
                        .frame(width: 1, height: 18)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 4)
                .stroke(STTheme.ruleHard, lineWidth: 1)
        )
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
                    .frame(minWidth: 180, alignment: .leading)

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
                RoundedRectangle(cornerRadius: 4)
                    .fill(STTheme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(STTheme.ruleHard, lineWidth: 1)
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
            .background(STTheme.panel)
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
                    .frame(minWidth: 180, alignment: .leading)

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
                RoundedRectangle(cornerRadius: 4)
                    .fill(STTheme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(STTheme.ruleHard, lineWidth: 1)
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
            .background(STTheme.panel)
        }
    }
}

private struct SliderControl: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        GeometryReader { geometry in
            let clamped = min(max(value, range.lowerBound), range.upperBound)
            let progress = (clamped - range.lowerBound) / (range.upperBound - range.lowerBound)
            let thumbOffset = progress * max(geometry.size.width - 14, 0)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(STTheme.rule)
                    .frame(height: 3)

                Capsule()
                    .fill(STTheme.accent)
                    .frame(width: max(14, thumbOffset + 14), height: 3)

                Circle()
                    .fill(STTheme.panel)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(STTheme.ruleHard, lineWidth: 1))
                    .offset(x: thumbOffset)
                    .shadow(color: STTheme.shadow, radius: 1.5, x: 0, y: 1)
            }
            .frame(height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let width = max(geometry.size.width, 1)
                        let normalized = min(max(gesture.location.x / width, 0), 1)
                        let raw = range.lowerBound + normalized * (range.upperBound - range.lowerBound)
                        let stepped = (raw / step).rounded() * step
                        value = min(max(stepped, range.lowerBound), range.upperBound)
                    }
            )
        }
        .frame(width: 160, height: 18)
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
                RoundedRectangle(cornerRadius: 3)
                    .stroke(STTheme.ruleHard, lineWidth: 1)
            )
    }
}
