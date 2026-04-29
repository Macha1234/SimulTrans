import SwiftUI
import Translation

struct OverlayContentView: View {
    @Environment(AppState.self) private var appState
    var onExport: (() -> Void)?

    private let timeFmt: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        @Bindable var appState = appState

        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(STTheme.bg.opacity(panelOpacity))
                .background(.ultraThinMaterial.opacity(panelOpacity * 0.92))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(STTheme.rule.opacity(panelOpacity), lineWidth: 1)
                )

            VStack(spacing: 0) {
                header
                columnHeader

                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if appState.transcriptEntries.isEmpty && appState.currentOriginalText.isEmpty {
                                standbyView()
                                    .id("standby")
                            } else {
                                ForEach(appState.transcriptEntries) { entry in
                                    entryView(entry: entry)
                                        .id(entry.id)
                                }

                                if !appState.currentOriginalText.isEmpty {
                                    liveEntryView()
                                        .id("live")
                                } else if appState.isRunning {
                                    listeningStateView()
                                        .id("listening")
                                }
                            }
                        }
                    }
                    .onChange(of: appState.currentOriginalText) {
                        guard !appState.currentOriginalText.isEmpty else { return }
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("live", anchor: .bottom)
                        }
                    }
                    .onChange(of: appState.transcriptEntries.count) {
                        guard let last = appState.transcriptEntries.last else { return }
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(appState.appearancePreference.colorScheme)
        .environment(\.locale, appState.overlayInterfaceLocale)
        .translationTask(appState.translationConfig) { session in
            appState.translationSession = session
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(appState.isRunning ? STTheme.green : STTheme.inkTertiary)
                .frame(width: 6, height: 6)

            Text(appState.isRunning ? "ON AIR" : "STANDBY", bundle: .module)
                .font(STTheme.monoFont(size: 9))
                .tracking(1.7)
                .foregroundStyle(STTheme.inkSecondary)

            if appState.isRunning, appState.sessionStartedAt != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("\(languageCode(for: appState.sourceLanguage)) → \(languageCode(for: appState.targetLanguage)) · \(AppState.formatElapsed(from: appState.sessionStartedAt, now: context.date))")
                        .font(STTheme.monoFont(size: 9, weight: .regular))
                        .foregroundStyle(STTheme.inkTertiary)
                }
            } else {
                Text("\(languageCode(for: appState.sourceLanguage)) → \(languageCode(for: appState.targetLanguage))")
                    .font(STTheme.monoFont(size: 9, weight: .regular))
                    .foregroundStyle(STTheme.inkTertiary)
            }

            Spacer()

            Text("\(appState.transcriptEntries.count) entries", bundle: .module)
                .font(STTheme.monoFont(size: 9, weight: .regular))
                .tracking(1.2)
                .foregroundStyle(STTheme.inkTertiary)
                .textCase(.uppercase)

            if !appState.transcriptEntries.isEmpty {
                Button(action: { onExport?() }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(STTheme.inkSecondary)
                }
                .buttonStyle(.plain)
                .help(overlayLocalizedString("Export transcript"))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(STTheme.bg.opacity(0.72 * panelOpacity))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(STTheme.rule.opacity(panelOpacity))
                .frame(height: 1)
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("TIME", bundle: .module)
                .frame(width: timeColumnWidth, alignment: .leading)

            Text("SOURCE ABOVE · \(languageName(for: appState.sourceLanguage))", bundle: .module)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 10)

            Text("TRANSLATION · \(languageName(for: appState.targetLanguage))", bundle: .module)
                .foregroundStyle(STTheme.accent)
        }
        .font(STTheme.monoFont(size: 9))
        .tracking(1.2)
        .foregroundStyle(STTheme.inkTertiary)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(STTheme.rule.opacity(panelOpacity))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func entryView(entry: TranscriptEntry) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(timeFmt.string(from: entry.timestamp))
                .font(STTheme.monoFont(size: 9, weight: .regular))
                .foregroundStyle(STTheme.inkTertiary)
                .frame(width: timeColumnWidth, alignment: .leading)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.originalText)
                    .font(STTheme.bodyFont(size: sourceFontSize))
                    .foregroundStyle(STTheme.inkSecondary)
                    .lineSpacing(2)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(entry.translatedText ?? "…")
                    .font(STTheme.displayFont(size: translationFontSize, weight: .medium))
                    .foregroundStyle(entry.translatedText == nil ? STTheme.inkTertiary : STTheme.ink)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.leading, 10)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(STTheme.rule.opacity(panelOpacity))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func liveEntryView() -> some View {
        ZStack(alignment: .leading) {
            STTheme.accentSoft.opacity(panelOpacity)

            Rectangle()
                .fill(STTheme.accent.opacity(panelOpacity))
                .frame(width: 3)

            HStack(alignment: .top, spacing: 0) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(STTheme.accent)
                        .frame(width: 5, height: 5)
                    Text(timeFmt.string(from: Date()))
                }
                .font(STTheme.monoFont(size: 9))
                .foregroundStyle(STTheme.accent)
                .frame(width: timeColumnWidth, alignment: .leading)
                .padding(.top, 3)

                VStack(alignment: .leading, spacing: 4) {
                    (
                        Text(appState.currentOriginalText)
                            .font(STTheme.bodyFont(size: sourceFontSize))
                            .foregroundStyle(STTheme.inkSecondary)
                        +
                        Text("▍")
                            .font(STTheme.bodyFont(size: sourceFontSize))
                            .foregroundStyle(STTheme.inkSecondary.opacity(0.45))
                    )
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(appState.currentTranslatedText.isEmpty ? "…" : appState.currentTranslatedText)
                        .font(STTheme.displayFont(size: translationFontSize, weight: .medium))
                        .foregroundStyle(appState.currentTranslatedText.isEmpty ? STTheme.inkTertiary : STTheme.ink)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, 10)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(STTheme.rule.opacity(panelOpacity))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func listeningStateView() -> some View {
        HStack(alignment: .center, spacing: 0) {
            Text("LIVE", bundle: .module)
                .font(STTheme.monoFont(size: 9))
                .foregroundStyle(STTheme.green)
                .frame(width: timeColumnWidth, alignment: .leading)

            HStack(spacing: 8) {
                Circle()
                    .fill(STTheme.green)
                    .frame(width: 5, height: 5)
                    .modifier(PulseModifier())

                Text("Waiting for the next speaker…", bundle: .module)
                    .font(STTheme.displayItalicFont(size: 18, weight: .regular))
                    .foregroundStyle(STTheme.inkSecondary)
            }
            .padding(.leading, 10)

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(STTheme.rule.opacity(panelOpacity))
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func standbyView() -> some View {
        VStack(spacing: 14) {
            WaveformPlaceholder()
                .foregroundStyle(STTheme.inkTertiary)

            Text("waiting for someone to speak…", bundle: .module)
                .font(STTheme.displayItalicFont(size: 18, weight: .regular))
                .foregroundStyle(STTheme.inkSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 140, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 24)
    }

    private var timeColumnWidth: CGFloat { 58 }

    private var panelOpacity: Double {
        min(max(appState.overlayOpacity, 0), 1)
    }

    private var sourceFontSize: CGFloat {
        max(10, appState.fontSize * 0.68)
    }

    private var translationFontSize: CGFloat {
        max(18, appState.fontSize * 1.28)
    }

    private func languageName(for selection: Locale.Language) -> String {
        AppState.localizedDisplayName(for: selection, in: appState.overlayInterfaceLocale)
    }

    private func languageCode(for selection: Locale.Language) -> String {
        let identifier = selection.minimalIdentifier.lowercased()
        if identifier.hasPrefix("zh") { return "ZH" }
        if identifier.hasPrefix("ja") { return "JA" }
        if identifier.hasPrefix("ko") { return "KO" }
        if identifier.hasPrefix("en") { return "EN" }
        if identifier.hasPrefix("pt") { return "PT" }
        if identifier.hasPrefix("es") { return "ES" }
        if identifier.hasPrefix("fr") { return "FR" }
        if identifier.hasPrefix("de") { return "DE" }
        if identifier.hasPrefix("it") { return "IT" }
        if identifier.hasPrefix("ru") { return "RU" }
        if identifier.hasPrefix("ar") { return "AR" }
        return selection.minimalIdentifier.prefix(2).uppercased()
    }

    private func overlayLocalizedString(_ key: String) -> String {
        appState.localizedOverlayString(key)
    }
}

private struct WaveformPlaceholder: View {
    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<18, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(STTheme.inkTertiary.opacity(0.28 + Double(index % 5) * 0.1))
                    .frame(width: 3, height: CGFloat(16 + ((index * 11) % 22)))
            }
        }
        .frame(height: 38)
    }
}

private struct PulseModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .opacity(0.85)
    }
}
