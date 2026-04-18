import SwiftUI

struct ControlWindowView: View {
    @Bindable var appState: AppState
    var onStart: () -> Void
    var onStop: () -> Void
    var onExport: () -> Void
    var onClear: () -> Void

    var body: some View {
        ZStack {
            STTheme.bg
                .overlay(alignment: .topLeading) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [STTheme.panel.opacity(0.55), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    masthead
                    inputSection
                    overlaySection

                    if let error = appState.errorMessage {
                        errorCard(error)
                    }

                    debugPanel

                    if !appState.isRunning && appState.transcriptEntries.isEmpty {
                        permissionNote
                    }

                    footerActions
                }
                .padding(22)
            }
        }
        .frame(minWidth: 480, minHeight: 780)
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                Text("VOL. 01 / LIVE ROOM")
                    .font(STTheme.monoFont(size: 10, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(STTheme.accent)

                (
                    Text("Simul")
                        .font(STTheme.displayFont(size: 38, weight: .medium))
                    +
                    Text("Trans")
                        .font(STTheme.displayFont(size: 38, weight: .regular))
                        .italic()
                )
                .foregroundStyle(STTheme.ink)
                .tracking(-1.2)

                HStack(spacing: 10) {
                    Circle()
                        .fill(appState.isRunning ? STTheme.green : STTheme.inkTertiary)
                        .frame(width: 6, height: 6)

                    Text(appState.isRunning ? "ON AIR" : "STANDBY")
                        .font(STTheme.monoFont(size: 11, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(STTheme.inkSecondary)

                    Text("·")
                        .foregroundStyle(STTheme.inkTertiary)

                    Text("\(compactLanguageName(for: appState.sourceLanguage)) → \(compactLanguageName(for: appState.targetLanguage))")
                        .font(STTheme.monoFont(size: 11, weight: .medium))
                        .foregroundStyle(STTheme.inkSecondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 24)
        }
        .background(cardBackground())
    }

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Input")

            VStack(spacing: 0) {
                panelRow(label: "音声入力") {
                    audioSourceSelector
                }
                panelDivider()
                panelRow(label: "音声の言語") {
                    languageMenu(selection: appState.sourceLanguage) { language in
                        appState.sourceLanguage = language.locale
                    }
                }
                panelDivider()
                panelRow(label: "翻訳先") {
                    languageMenu(selection: appState.targetLanguage) { language in
                        appState.targetLanguage = language.locale
                    }
                }
            }
            .background(panelBackground())
        }
    }

    private var overlaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader("Overlay")

            VStack(spacing: 0) {
                panelRow(label: "不透明度") {
                    VStack(alignment: .trailing, spacing: 6) {
                        Slider(value: $appState.overlayOpacity, in: 0.3...1.0, step: 0.05)
                            .frame(width: 170)
                            .tint(STTheme.accent)
                        Text("\(Int(appState.overlayOpacity * 100))%")
                            .font(STTheme.monoFont(size: 10))
                            .foregroundStyle(STTheme.inkTertiary)
                    }
                }
                panelDivider()
                panelRow(label: "文字サイズ") {
                    VStack(alignment: .trailing, spacing: 6) {
                        Slider(value: $appState.fontSize, in: 12...28, step: 1)
                            .frame(width: 170)
                            .tint(STTheme.accent)
                        Text("\(Int(appState.fontSize)) pt")
                            .font(STTheme.monoFont(size: 10))
                            .foregroundStyle(STTheme.inkTertiary)
                    }
                }
            }
            .background(panelBackground())
        }
    }

    private func errorCard(_ error: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SYSTEM NOTE")
                .font(STTheme.monoFont(size: 10, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(STTheme.accent)

            Text(error)
                .font(.system(size: 13))
                .foregroundStyle(STTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(cardBackground(fill: STTheme.accentSoft))
    }

    private var permissionNote: some View {
        Text(appState.audioSource == .system
             ? "システム音声を翻訳するには、初回起動時に画面収録の許可が必要です。"
             : "マイク音声を翻訳するには、初回起動時にマイクへのアクセス許可が必要です。")
            .font(.system(size: 13))
            .foregroundStyle(STTheme.inkSecondary)
            .multilineTextAlignment(.leading)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground(fill: STTheme.panelAlt.opacity(0.65)))
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
                    Text(appState.isRunning ? "翻訳を停止" : "翻訳を開始")
                        .font(STTheme.monoFont(size: 12, weight: .semibold))
                        .tracking(2)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(appState.isRunning ? Color.white : STTheme.bg)
                .background(appState.isRunning ? STTheme.accent : STTheme.ink)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                secondaryButton("書き出す", action: onExport)
                secondaryButton("履歴を消去", action: onClear)
            }

            HStack {
                Text("\(appState.transcriptEntries.count) entries recorded")
                Spacer()
                Text(versionString)
            }
            .font(STTheme.monoFont(size: 10))
            .tracking(1)
            .foregroundStyle(STTheme.inkTertiary)
        }
        .padding(16)
        .background(cardBackground())
    }

    private var debugPanel: some View {
        DisclosureGroup(isExpanded: $appState.debugPanelExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(appState.recognitionPhase.capitalized, systemImage: "waveform.path.ecg")
                        .font(STTheme.monoFont(size: 10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(STTheme.inkSecondary)

                    Spacer()

                    Text("raw \(appState.rawRecognitionText.count)")
                        .font(STTheme.monoFont(size: 10))
                        .foregroundStyle(STTheme.inkTertiary)
                }

                debugTextBlock(title: "Raw recognizer text", text: appState.rawRecognitionText)
                debugTextBlock(title: "Effective text after processing", text: appState.effectiveRecognitionText)
                debugTextBlock(title: "Displayed live text", text: appState.currentOriginalText)
                debugTextBlock(title: "Current translation", text: appState.currentTranslatedText)
                debugTextBlock(title: "Last final recognizer text", text: appState.lastFinalRecognitionText)

                if !appState.debugRecognitionEntries.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent recognition updates")
                            .font(STTheme.monoFont(size: 10, weight: .semibold))
                            .tracking(1.5)
                            .foregroundStyle(STTheme.inkTertiary)

                        ForEach(appState.debugRecognitionEntries) { entry in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(entry.phase.uppercased())
                                        .font(STTheme.monoFont(size: 10, weight: .semibold))
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
                            .padding(12)
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
            .padding(.top, 8)
        } label: {
            Text("Debug Recognition")
                .font(STTheme.displayFont(size: 18, weight: .medium))
                .foregroundStyle(STTheme.ink)
        }
        .padding(18)
        .background(cardBackground(fill: STTheme.panelAlt.opacity(0.55)))
    }

    private var audioSourceSelector: some View {
        HStack(spacing: 0) {
            ForEach(AppState.AudioSource.allCases, id: \.self) { source in
                Button {
                    guard !appState.isRunning else { return }
                    appState.audioSource = source
                } label: {
                    Text(source.rawValue)
                        .font(STTheme.monoFont(size: 11, weight: .semibold))
                        .tracking(0.7)
                        .foregroundStyle(appState.audioSource == source ? STTheme.bg : STTheme.inkSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(appState.audioSource == source ? STTheme.ink : Color.clear)
                }
                .buttonStyle(.plain)
                .disabled(appState.isRunning)

                if source != AppState.AudioSource.allCases.last {
                    Divider()
                        .frame(height: 18)
                        .overlay(STTheme.ruleHard)
                }
            }
        }
        .padding(2)
        .frame(minWidth: 220)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(STTheme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(STTheme.ruleHard, lineWidth: 1)
                )
        )
        .opacity(appState.isRunning ? 0.6 : 1)
    }

    private func languageMenu(selection: Locale.Language,
                              onSelect: @escaping (AppState.SupportedLanguage) -> Void) -> some View {
        Menu {
            ForEach(AppState.supportedLanguages) { language in
                Button(language.name) {
                    onSelect(language)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(languageName(for: selection))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(STTheme.ink)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(STTheme.inkTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(STTheme.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(STTheme.ruleHard, lineWidth: 1)
                    )
            )
        }
        .menuStyle(.borderlessButton)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(STTheme.monoFont(size: 11, weight: .semibold))
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

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(STTheme.monoFont(size: 10, weight: .semibold))
            .tracking(2)
            .foregroundStyle(STTheme.inkTertiary)
    }

    private func panelRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(STTheme.inkSecondary)

            Spacer(minLength: 12)

            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func panelDivider() -> some View {
        Rectangle()
            .fill(STTheme.rule)
            .frame(height: 1)
            .padding(.horizontal, 16)
    }

    private func panelBackground() -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(STTheme.panel)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(STTheme.rule, lineWidth: 1)
            )
    }

    private func cardBackground(fill: Color = STTheme.panel) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(fill)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(STTheme.rule, lineWidth: 1)
            )
            .shadow(color: STTheme.shadow, radius: 12, x: 0, y: 6)
    }

    private func debugTextBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(STTheme.monoFont(size: 10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(STTheme.inkTertiary)

            Text(text.isEmpty ? "No data yet" : text)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(text.isEmpty ? STTheme.inkTertiary : STTheme.ink)
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
                .font(STTheme.monoFont(size: 10, weight: .semibold))
                .foregroundStyle(STTheme.inkTertiary)
                .frame(width: 64, alignment: .leading)

            Text(text.isEmpty ? "empty" : text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(text.isEmpty ? STTheme.inkTertiary : STTheme.inkSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func languageName(for selection: Locale.Language) -> String {
        AppState.supportedLanguages.first { $0.id == selection.minimalIdentifier }?.name ?? selection.minimalIdentifier
    }

    private func compactLanguageName(for selection: Locale.Language) -> String {
        let name = languageName(for: selection)
        return name.replacingOccurrences(of: "（米国）", with: "")
            .replacingOccurrences(of: "（英国）", with: "")
            .replacingOccurrences(of: "（ブラジル）", with: "")
            .replacingOccurrences(of: "（簡体字）", with: "")
            .replacingOccurrences(of: "（繁体字）", with: "")
    }

    private var versionString: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}
