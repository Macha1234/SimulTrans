import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: Tab = .general

    enum Tab: String, CaseIterable, Identifiable {
        case general = "General"
        case languages = "Languages"
        case overlay = "Overlay"
        case hotkeys = "Hotkeys"
        case export = "Export"
        case advanced = "Advanced"

        var id: String { rawValue }
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
        .onChange(of: appState.sourceLanguage) { appState.updateTranslationConfig() }
        .onChange(of: appState.targetLanguage) { appState.updateTranslationConfig() }
        .onChange(of: appState.appearancePreference) { _, newValue in
            NSApp.appearance = newValue.nsAppearance
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Settings")
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
                    Text(tab.rawValue)
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
                contentHeader(eyebrow: selectedTab.rawValue.uppercased(),
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
        case .general:   return "How SimulTrans behaves."
        case .languages: return "Source and target."
        case .overlay:   return "How the floating window looks."
        case .hotkeys:   return "Keyboard shortcuts."
        case .export:    return "Saving transcripts."
        case .advanced:  return "Diagnostics and engine."
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

        SetRow(label: "Launch at login") {
            STSwitch(isOn: $appState.launchAtLogin)
        }
        SetRow(label: "Show menu bar icon") {
            STSwitch(isOn: $appState.showMenuBarIcon)
        }
        SetRow(label: "Hide dock icon",
               hint: "Run as a pure menu bar app (takes effect on next launch).") {
            STSwitch(isOn: $appState.hideDockIcon)
        }
        SetRow(label: "Dim overlay when silent",
               hint: "Fades the overlay to ~30% opacity after 10s of silence.") {
            STSwitch(isOn: $appState.dimOverlayWhenSilent)
        }
        SetRow(label: "Theme") {
            STSegmented(options: AppearancePreference.allCases.map { ($0, $0.label) },
                        selected: $appState.appearancePreference)
        }
    }

    // MARK: - Languages

    @ViewBuilder
    private func languagesRows(appState: AppState) -> some View {
        @Bindable var appState = appState

        SetRow(label: "Source language",
               hint: "What you expect to hear.") {
            LanguagePicker(selection: $appState.sourceLanguage)
        }
        SetRow(label: "Translate to",
               hint: "Apple Translation runs on-device when the language pair is downloaded.") {
            LanguagePicker(selection: $appState.targetLanguage)
        }
    }

    // MARK: - Overlay

    @ViewBuilder
    private func overlayRows(appState: AppState) -> some View {
        @Bindable var appState = appState

        SetRow(label: "Opacity",
               hint: "Background opacity of the floating overlay.") {
            SliderControl(value: $appState.overlayOpacity, range: 0.3...1.0, step: 0.05)
        }
        SetRow(label: "Text size · \(Int(appState.fontSize)) pt") {
            SliderControl(value: Binding(get: { Double(appState.fontSize) },
                                         set: { appState.fontSize = CGFloat($0) }),
                          range: 12...26,
                          step: 1)
        }
    }

    // MARK: - Hotkeys / Export placeholders

    @ViewBuilder
    private func hotkeysRows() -> some View {
        SetRow(label: "Toggle overlay",
               hint: "Coming soon — global shortcut to show / hide the floating window.") {
            HotkeyChip(text: "⌘⇧T")
        }
        SetRow(label: "Start / stop translation",
               hint: "Coming soon.") {
            HotkeyChip(text: "⌘⇧Space")
        }
    }

    @ViewBuilder
    private func exportRows() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SetRow(label: "Default format",
                   hint: "Plain text with timestamp + source + translation.") {
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
            SetRow(label: "Open exported files",
                   hint: "Reveals each export in Finder after saving.") {
                STSwitch(isOn: .constant(true))
                    .opacity(0.6)
            }
        }
    }

    // MARK: - Advanced

    @ViewBuilder
    private func advancedRows(appState: AppState) -> some View {
        @Bindable var appState = appState

        SetRow(label: "Translation engine",
               hint: "Runs locally via Apple Translation.") {
            Text("On-device")
                .font(STTheme.bodyFont(size: 13, weight: .medium))
                .foregroundStyle(STTheme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(STTheme.ruleHard, lineWidth: 1)
                )
        }

        SetRow(label: "Show debug recognition panel",
               hint: "Surface raw / effective / displayed text in the control window for tuning.") {
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
    @Binding var selection: Locale.Language
    @State private var presented = false

    var body: some View {
        Button {
            presented.toggle()
        } label: {
            HStack(spacing: 0) {
                Text(matchedSupportedLanguage(for: selection)?.name ?? selection.minimalIdentifier)
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
                                Text(language.name)
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
        let minimal = selection.minimalIdentifier.lowercased()
        return AppState.supportedLanguages.first { language in
            let candidate = language.id.lowercased()
            return candidate == minimal || candidate.hasPrefix("\(minimal)-") || minimal.hasPrefix(candidate)
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
