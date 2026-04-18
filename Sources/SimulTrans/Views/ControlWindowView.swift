import SwiftUI

struct ControlWindowView: View {
    @Bindable var appState: AppState
    var onStart: () -> Void
    var onStop: () -> Void
    var onExport: () -> Void
    var onClear: () -> Void

    @State private var sourceLanguageMenuPresented = false
    @State private var targetLanguageMenuPresented = false

    var body: some View {
        ZStack {
            STTheme.bg
                .ignoresSafeArea()

            VStack(spacing: 0) {
                masthead

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        inputSection
                        overlaySection

                        if let error = appState.errorMessage {
                            errorCard(error)
                        }

                        debugPanel

                        if !appState.isRunning && appState.transcriptEntries.isEmpty {
                            permissionNote
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 18)
                }

                footerActions
            }
        }
        .frame(minWidth: STTheme.controlWindowSize.width, minHeight: STTheme.controlWindowSize.height)
        .preferredColorScheme(appState.appearancePreference.colorScheme)
        .onChange(of: appState.appearancePreference) { _, newValue in
            NSApp.appearance = newValue.nsAppearance
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("vol. 01 / live room", bundle: .module)
                .font(STTheme.monoFont(size: 10))
                .tracking(2)
                .foregroundStyle(STTheme.accent)
                .textCase(.uppercase)
                .padding(.bottom, 8)

            (
                Text("Simul")
                    .font(STTheme.displayFont(size: 40, weight: .medium))
                +
                Text("Trans")
                    .font(STTheme.displayItalicFont(size: 40, weight: .regular))
            )
            .tracking(-1.4)
            .foregroundStyle(STTheme.ink)

            HStack(spacing: 10) {
                Circle()
                    .fill(appState.isRunning ? STTheme.green : STTheme.inkTertiary)
                    .frame(width: 6, height: 6)

                if appState.isRunning, appState.sessionStartedAt != nil {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("ON AIR · \(AppState.formatElapsed(from: appState.sessionStartedAt, now: context.date))", bundle: .module)
                            .font(STTheme.monoFont(size: 11))
                            .tracking(1.8)
                            .foregroundStyle(STTheme.inkSecondary)
                    }
                } else {
                    Text("STANDBY", bundle: .module)
                        .font(STTheme.monoFont(size: 11))
                        .tracking(1.8)
                        .foregroundStyle(STTheme.inkSecondary)
                }

                Text("·")
                    .foregroundStyle(STTheme.inkTertiary)

                Text("\(languageCode(for: appState.sourceLanguage)) → \(languageCode(for: appState.targetLanguage))")
                    .font(STTheme.monoFont(size: 11))
                    .foregroundStyle(STTheme.inkSecondary)
            }
            .padding(.top, 10)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(STTheme.rule)
                .frame(height: 1)
        }
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Input")

            VStack(spacing: 0) {
                fieldRow {
                    Text("Audio Input", bundle: .module)
                        .font(STTheme.bodyFont(size: 13))
                        .foregroundStyle(STTheme.inkSecondary)
                } control: {
                    audioSourceSelector
                }

                fieldDivider()

                fieldRow {
                    Text("Source Language", bundle: .module)
                        .font(STTheme.bodyFont(size: 13))
                        .foregroundStyle(STTheme.inkSecondary)
                } control: {
                    languageDropdown(selection: appState.sourceLanguage,
                                     isPresented: $sourceLanguageMenuPresented) { language in
                        appState.sourceLanguage = language.locale
                    }
                }

                fieldDivider()

                fieldRow {
                    Text("Translate To", bundle: .module)
                        .font(STTheme.bodyFont(size: 13))
                        .foregroundStyle(STTheme.inkSecondary)
                } control: {
                    languageDropdown(selection: appState.targetLanguage,
                                     isPresented: $targetLanguageMenuPresented) { language in
                        appState.targetLanguage = language.locale
                    }
                }
            }
            .background(surface(fill: STTheme.panel))
        }
    }

    private var overlaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Overlay")

            VStack(spacing: 0) {
                fieldRow {
                    Text("Opacity", bundle: .module)
                        .font(STTheme.bodyFont(size: 13))
                        .foregroundStyle(STTheme.inkSecondary)
                } control: {
                    StudioSlider(value: $appState.overlayOpacity,
                                 range: 0.3...1.0,
                                 step: 0.05,
                                 width: 140)
                }

                fieldDivider()

                fieldRow {
                    HStack(spacing: 4) {
                        Text("Text Size · \(Int(appState.fontSize)) pt")
                            .font(STTheme.monoFont(size: 11))
                            .foregroundStyle(STTheme.ink)
                    }
                } control: {
                    StudioSlider(value: Binding(
                        get: { Double(appState.fontSize) },
                        set: { appState.fontSize = CGFloat($0) }
                    ), range: 12...26,
                    step: 1,
                    width: 140)
                }
            }
            .background(surface(fill: STTheme.panel))
        }
    }

    private func errorCard(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("System note")
                .font(STTheme.monoFont(size: 10))
                .tracking(1.8)
                .foregroundStyle(STTheme.accent)
                .textCase(.uppercase)

            Text(error)
                .font(STTheme.bodyFont(size: 13))
                .foregroundStyle(STTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(surface(fill: STTheme.accentSoft))
    }

    private var permissionNote: some View {
        Text(appState.audioSource == .system
             ? "Screen Recording permission is required the first time you translate system audio."
             : "Microphone permission is required the first time you translate microphone input.")
            .font(STTheme.bodyFont(size: 13))
            .foregroundStyle(STTheme.inkSecondary)
            .multilineTextAlignment(.leading)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(surface(fill: STTheme.panelAlt.opacity(0.72)))
    }

    private var footerActions: some View {
        VStack(spacing: 10) {
            Button(action: {
                if appState.isRunning {
                    onStop()
                } else {
                    onStart()
                }
            }) {
                HStack(spacing: 10) {
                    Rectangle()
                        .fill(appState.isRunning ? Color.white.opacity(0.95) : STTheme.bg)
                        .frame(width: 9, height: 9)

                    Text(appState.isRunning ? "STOP TRANSLATION" : "START TRANSLATION", bundle: .module)
                        .font(STTheme.monoFont(size: 12))
                        .tracking(2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(Color.white)
                .background(STTheme.accent)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                secondaryButton("EXPORT", action: onExport)
                secondaryButton("CLEAR HISTORY", action: onClear)
            }

            HStack {
                Text("\(appState.transcriptEntries.count) entries recorded", bundle: .module)
                Spacer()
                Text(versionString)
            }
            .font(STTheme.monoFont(size: 10))
            .tracking(1)
            .foregroundStyle(STTheme.inkTertiary)
        }
        .padding(16)
        .background(STTheme.panel)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(STTheme.rule)
                .frame(height: 1)
        }
    }

    private var debugPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Debug")

            DisclosureGroup(isExpanded: $appState.debugPanelExpanded) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        debugBlock(title: "Raw recognizer text", text: appState.rawRecognitionText)
                        debugBlock(title: "Effective text", text: appState.effectiveRecognitionText)
                        debugBlock(title: "Displayed live text", text: appState.currentOriginalText)
                        debugBlock(title: "Current translation", text: appState.currentTranslatedText)
                        debugBlock(title: "Last final recognizer text", text: appState.lastFinalRecognitionText)

                        if !appState.debugRecognitionEntries.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Recent recognition updates")
                                    .font(STTheme.monoFont(size: 10))
                                    .tracking(1.6)
                                    .foregroundStyle(STTheme.inkTertiary)
                                    .textCase(.uppercase)

                                ForEach(appState.debugRecognitionEntries) { entry in
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Text(entry.phase.uppercased())
                                                .font(STTheme.monoFont(size: 10))
                                                .foregroundStyle(entry.phase == "final" ? STTheme.green : STTheme.accent)

                                            Spacer()

                                            Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                                .font(STTheme.monoFont(size: 10))
                                                .foregroundStyle(STTheme.inkTertiary)
                                        }

                                        debugSnapshotRow(title: "raw", text: entry.rawText)
                                        debugSnapshotRow(title: "effective", text: entry.effectiveText)
                                        debugSnapshotRow(title: "shown", text: entry.displayedText)
                                    }
                                    .padding(10)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(STTheme.panel)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(STTheme.rule, lineWidth: 1)
                                            )
                                    )
                                }
                            }
                        }
                    }
                    .padding(.top, 10)
                }
                .frame(maxHeight: 248)
            } label: {
                HStack(spacing: 10) {
                    Text("Debug recognition")
                        .font(STTheme.displayFont(size: 16, weight: .medium))
                        .foregroundStyle(STTheme.ink)

                    Spacer()

                    Text(appState.recognitionPhase.uppercased())
                        .font(STTheme.monoFont(size: 10))
                        .tracking(1.4)
                        .foregroundStyle(STTheme.inkSecondary)

                    Text("raw \(appState.rawRecognitionText.count)")
                        .font(STTheme.monoFont(size: 10))
                        .foregroundStyle(STTheme.inkTertiary)
                }
            }
            .padding(14)
            .background(surface(fill: STTheme.panelAlt.opacity(0.72)))
        }
    }

    private var audioSourceSelector: some View {
        HStack(spacing: 0) {
            ForEach(AppState.AudioSource.allCases, id: \.self) { source in
                Button {
                    guard !appState.isRunning else { return }
                    appState.audioSource = source
                } label: {
                    Text(source.localizedName)
                        .font(STTheme.monoFont(size: 11))
                        .tracking(0.5)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .foregroundStyle(appState.audioSource == source ? STTheme.bg : STTheme.inkSecondary)
                        .background(appState.audioSource == source ? STTheme.ink : Color.clear)
                }
                .buttonStyle(.plain)
                .disabled(appState.isRunning)

                if source != AppState.AudioSource.allCases.last {
                    Rectangle()
                        .fill(STTheme.ruleHard)
                        .frame(width: 1, height: 18)
                }
            }
        }
        .padding(2)
        .frame(width: 228)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .stroke(STTheme.ruleHard, lineWidth: 1)
        )
        .opacity(appState.isRunning ? 0.58 : 1)
    }

    private func languageDropdown(selection: Locale.Language,
                                  isPresented: Binding<Bool>,
                                  onSelect: @escaping (AppState.SupportedLanguage) -> Void) -> some View {
        Button {
            isPresented.wrappedValue.toggle()
        } label: {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    if let flag = matchedSupportedLanguage(for: selection)?.flag {
                        Text(flag).font(.system(size: 14))
                    }
                    Text(languageName(for: selection))
                        .font(STTheme.bodyFont(size: 13, weight: .medium))
                        .foregroundStyle(STTheme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(minWidth: 150, alignment: .leading)

                Rectangle()
                    .fill(STTheme.ruleHard)
                    .frame(width: 1, height: 16)
                    .padding(.vertical, 7)

                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(STTheme.inkTertiary)
                    .frame(width: 34, height: 32)
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
        .popover(isPresented: isPresented, arrowEdge: .top) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(AppState.supportedLanguages) { language in
                        Button {
                            onSelect(language)
                            isPresented.wrappedValue = false
                        } label: {
                            HStack(spacing: 10) {
                                Text(language.flag).font(.system(size: 16))
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(language.nativeName)
                                        .font(STTheme.bodyFont(size: 13, weight: .medium))
                                        .foregroundStyle(STTheme.ink)
                                    if language.nativeName != language.name {
                                        Text(language.name)
                                            .font(STTheme.monoFont(size: 9))
                                            .tracking(0.6)
                                            .foregroundStyle(STTheme.inkTertiary)
                                    }
                                }
                                Spacer()
                                if language.id == matchedSupportedLanguage(for: selection)?.id {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(STTheme.accent)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
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
            .frame(width: 260, height: 340)
            .padding(8)
            .background(STTheme.panel)
        }
    }

    private func secondaryButton(_ titleKey: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(titleKey, bundle: .module)
                .font(STTheme.monoFont(size: 11))
                .tracking(1.5)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .foregroundStyle(STTheme.ink)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(STTheme.ruleHard, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ key: LocalizedStringKey) -> some View {
        Text(key, bundle: .module)
            .font(STTheme.monoFont(size: 10))
            .tracking(2)
            .foregroundStyle(STTheme.inkTertiary)
            .textCase(.uppercase)
    }

    private func fieldRow<Label: View, Control: View>(
        @ViewBuilder label: () -> Label,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            label()
            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .frame(minHeight: 44)
    }

    private func fieldDivider() -> some View {
        Rectangle()
            .fill(STTheme.rule)
            .frame(height: 1)
            .padding(.horizontal, 16)
    }

    private func surface(fill: Color) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(STTheme.rule, lineWidth: 1)
            )
    }

    private func debugBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(STTheme.monoFont(size: 10))
                .tracking(1.2)
                .foregroundStyle(STTheme.inkTertiary)

            Text(text.isEmpty ? "No data yet" : text)
                .font(STTheme.monoFont(size: 11, weight: .regular))
                .foregroundStyle(text.isEmpty ? STTheme.inkTertiary : STTheme.inkSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(STTheme.panel)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(STTheme.rule, lineWidth: 1)
                        )
                )
        }
    }

    private func debugSnapshotRow(title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title)
                .font(STTheme.monoFont(size: 10))
                .foregroundStyle(STTheme.inkTertiary)
                .frame(width: 58, alignment: .leading)

            Text(text.isEmpty ? "empty" : text)
                .font(STTheme.monoFont(size: 10, weight: .regular))
                .foregroundStyle(text.isEmpty ? STTheme.inkTertiary : STTheme.inkSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func matchedSupportedLanguage(for selection: Locale.Language) -> AppState.SupportedLanguage? {
        let minimal = selection.minimalIdentifier.lowercased()
        return AppState.supportedLanguages.first { language in
            let candidate = language.id.lowercased()
            return candidate == minimal || candidate.hasPrefix("\(minimal)-") || minimal.hasPrefix(candidate)
        }
    }

    private func languageName(for selection: Locale.Language) -> String {
        matchedSupportedLanguage(for: selection)?.name ?? selection.minimalIdentifier
    }

    private func languageCode(for selection: Locale.Language) -> String {
        let identifier = matchedSupportedLanguage(for: selection)?.id ?? selection.minimalIdentifier
        let normalized = identifier.lowercased()

        if normalized.hasPrefix("zh") { return "ZH" }
        if normalized.hasPrefix("ja") { return "JA" }
        if normalized.hasPrefix("ko") { return "KO" }
        if normalized.hasPrefix("en") { return "EN" }
        if normalized.hasPrefix("pt") { return "PT" }
        if normalized.hasPrefix("es") { return "ES" }
        if normalized.hasPrefix("fr") { return "FR" }
        if normalized.hasPrefix("de") { return "DE" }
        if normalized.hasPrefix("it") { return "IT" }
        if normalized.hasPrefix("ru") { return "RU" }
        if normalized.hasPrefix("ar") { return "AR" }
        return identifier.prefix(2).uppercased()
    }

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}

private struct StudioSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let width: CGFloat

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
                    .overlay(
                        Circle()
                            .stroke(STTheme.ruleHard, lineWidth: 1)
                    )
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
                        let rawValue = range.lowerBound + normalized * (range.upperBound - range.lowerBound)
                        let stepped = (rawValue / step).rounded() * step
                        value = min(max(stepped, range.lowerBound), range.upperBound)
                    }
            )
        }
        .frame(width: width, height: 18)
    }
}
