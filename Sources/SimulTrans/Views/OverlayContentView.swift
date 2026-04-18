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
                .fill(STTheme.bg.opacity(appState.overlayOpacity))
                .background(.ultraThinMaterial.opacity(0.92))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(STTheme.rule, lineWidth: 1)
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
        .translationTask(appState.translationConfig) { session in
            appState.translationSession = session
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(appState.isRunning ? STTheme.green : STTheme.inkTertiary)
                .frame(width: 7, height: 7)

            Text(appState.isRunning ? "ON AIR" : "STANDBY")
                .font(STTheme.monoFont(size: 10))
                .tracking(2)
                .foregroundStyle(STTheme.inkSecondary)

            if appState.isRunning, appState.sessionStartedAt != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("\(languageCode(for: appState.sourceLanguage)) → \(languageCode(for: appState.targetLanguage)) · \(AppState.formatElapsed(from: appState.sessionStartedAt, now: context.date))")
                        .font(STTheme.monoFont(size: 10, weight: .regular))
                        .foregroundStyle(STTheme.inkTertiary)
                }
            } else {
                Text("\(languageCode(for: appState.sourceLanguage)) → \(languageCode(for: appState.targetLanguage))")
                    .font(STTheme.monoFont(size: 10, weight: .regular))
                    .foregroundStyle(STTheme.inkTertiary)
            }

            Spacer()

            Text("\(appState.transcriptEntries.count) ENTRIES")
                .font(STTheme.monoFont(size: 10, weight: .regular))
                .tracking(1.4)
                .foregroundStyle(STTheme.inkTertiary)

            if !appState.transcriptEntries.isEmpty {
                Button(action: { onExport?() }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(STTheme.inkSecondary)
                }
                .buttonStyle(.plain)
                .help("Export transcript")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(STTheme.bg.opacity(0.72))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(STTheme.rule)
                .frame(height: 1)
        }
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("TIME")
                .frame(width: 64, alignment: .leading)

            Text("SOURCE · \(languageName(for: appState.sourceLanguage))")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)

            Text("TRANSLATION · \(languageName(for: appState.targetLanguage))")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
        }
        .font(STTheme.monoFont(size: 10))
        .tracking(1.5)
        .foregroundStyle(STTheme.inkTertiary)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(STTheme.rule)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func entryView(entry: TranscriptEntry) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(timeFmt.string(from: entry.timestamp))
                .font(STTheme.monoFont(size: 10, weight: .regular))
                .foregroundStyle(STTheme.inkTertiary)
                .frame(width: 64, alignment: .leading)
                .padding(.top, 2)

            Text(entry.originalText)
                .font(STTheme.bodyFont(size: max(14, appState.fontSize - 2)))
                .foregroundStyle(STTheme.inkSecondary)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
                .padding(.trailing, 12)

            Text(entry.translatedText ?? "…")
                .font(STTheme.displayFont(size: max(15, appState.fontSize - 1), weight: .medium))
                .foregroundStyle(entry.translatedText == nil ? STTheme.inkTertiary : STTheme.ink)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(STTheme.rule)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func liveEntryView() -> some View {
        ZStack(alignment: .leading) {
            STTheme.accentSoft

            Rectangle()
                .fill(STTheme.accent)
                .frame(width: 3)

            HStack(alignment: .top, spacing: 0) {
                HStack(spacing: 5) {
                    Circle()
                        .fill(STTheme.accent)
                        .frame(width: 6, height: 6)
                    Text(timeFmt.string(from: Date()))
                }
                .font(STTheme.monoFont(size: 10))
                .foregroundStyle(STTheme.accent)
                .frame(width: 64, alignment: .leading)
                .padding(.top, 2)

                (
                    Text(appState.currentOriginalText)
                        .font(STTheme.bodyFont(size: max(14, appState.fontSize - 2)))
                        .foregroundStyle(STTheme.inkSecondary)
                    +
                    Text("▍")
                        .font(STTheme.bodyFont(size: max(14, appState.fontSize - 2)))
                        .foregroundStyle(STTheme.inkSecondary.opacity(0.45))
                )
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
                .padding(.trailing, 12)

                Text(appState.currentTranslatedText.isEmpty ? "…" : appState.currentTranslatedText)
                    .font(STTheme.displayFont(size: max(15, appState.fontSize - 1), weight: .medium))
                    .foregroundStyle(appState.currentTranslatedText.isEmpty ? STTheme.inkTertiary : STTheme.ink)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 14)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(STTheme.rule)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func listeningStateView() -> some View {
        HStack(alignment: .center, spacing: 0) {
            Text("LIVE")
                .font(STTheme.monoFont(size: 10))
                .foregroundStyle(STTheme.green)
                .frame(width: 64, alignment: .leading)

            HStack(spacing: 8) {
                Circle()
                    .fill(STTheme.green)
                    .frame(width: 6, height: 6)
                    .modifier(PulseModifier())

                Text("Waiting for the next speaker…")
                    .font(STTheme.displayItalicFont(size: 22, weight: .regular))
                    .foregroundStyle(STTheme.inkSecondary)
            }
            .padding(.leading, 14)

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(STTheme.rule)
                .frame(height: 1)
        }
    }

    @ViewBuilder
    private func standbyView() -> some View {
        VStack(spacing: 14) {
            WaveformPlaceholder()
                .foregroundStyle(STTheme.inkTertiary)

            Text("waiting for someone to speak…")
                .font(STTheme.displayItalicFont(size: 22, weight: .regular))
                .foregroundStyle(STTheme.inkSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
        .padding(.horizontal, 32)
        .padding(.vertical, 32)
    }

    private func languageName(for selection: Locale.Language) -> String {
        let minimal = selection.minimalIdentifier.lowercased()
        let match = AppState.supportedLanguages.first { language in
            let candidate = language.id.lowercased()
            return candidate == minimal || candidate.hasPrefix("\(minimal)-") || minimal.hasPrefix(candidate)
        }
        return match?.name ?? selection.minimalIdentifier
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
