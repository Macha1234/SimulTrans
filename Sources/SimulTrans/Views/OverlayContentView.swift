import SwiftUI
import Translation

struct OverlayContentView: View {
    @Environment(AppState.self) private var appState
    var onExport: (() -> Void)?

    private let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        @Bindable var appState = appState

        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(STTheme.bg.opacity(appState.overlayOpacity))
                .background(.ultraThinMaterial.opacity(0.82))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(STTheme.rule, lineWidth: 1)
                )

            VStack(spacing: 0) {
                header
                columnHeader

                ScrollViewReader { proxy in
                    ScrollView {
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
                        withAnimation(.easeOut(duration: 0.15)) {
                            if !appState.currentOriginalText.isEmpty {
                                proxy.scrollTo("live", anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: appState.transcriptEntries.count) {
                        if let last = appState.transcriptEntries.last {
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .translationTask(appState.translationConfig) { session in
            appState.translationSession = session
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(appState.isRunning ? STTheme.green : STTheme.inkTertiary)
                .frame(width: 7, height: 7)

            Text(appState.isRunning ? "ON AIR" : "STANDBY")
                .font(STTheme.monoFont(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(STTheme.inkSecondary)

            Text("\(compactLanguageName(for: appState.sourceLanguage)) → \(compactLanguageName(for: appState.targetLanguage))")
                .font(STTheme.monoFont(size: 10))
                .foregroundStyle(STTheme.inkTertiary)

            Spacer()

            Text("\(appState.transcriptEntries.count) ENTRIES")
                .font(STTheme.monoFont(size: 10))
                .tracking(1.2)
                .foregroundStyle(STTheme.inkTertiary)

            if !appState.transcriptEntries.isEmpty {
                Button(action: { onExport?() }) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(STTheme.inkSecondary)
                }
                .buttonStyle(.plain)
                .help("履歴を書き出す")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(STTheme.bg.opacity(0.72))
    }

    private var columnHeader: some View {
        HStack(spacing: 0) {
            Text("TIME")
                .frame(width: 64, alignment: .leading)

            Text("SOURCE · \(compactLanguageName(for: appState.sourceLanguage))")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)

            Text("TRANSLATION · \(compactLanguageName(for: appState.targetLanguage))")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
        }
        .font(STTheme.monoFont(size: 10, weight: .semibold))
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
                .font(STTheme.monoFont(size: 10))
                .foregroundStyle(STTheme.inkTertiary)
                .frame(width: 64, alignment: .leading)
                .padding(.top, 2)

            Text(entry.originalText)
                .font(.system(size: max(13, appState.fontSize - 1)))
                .foregroundStyle(STTheme.inkSecondary)
                .lineSpacing(4)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
                .padding(.trailing, 12)

            Text(entry.translatedText ?? "…")
                .font(STTheme.displayFont(size: max(14, appState.fontSize), weight: .semibold))
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
                Text(timeFmt.string(from: Date()))
                    .font(STTheme.monoFont(size: 10, weight: .semibold))
                    .foregroundStyle(STTheme.accent)
                    .frame(width: 64, alignment: .leading)
                    .padding(.top, 2)

                HStack(alignment: .bottom, spacing: 3) {
                    Text(appState.currentOriginalText)
                    + Text("▍")
                        .foregroundStyle(STTheme.inkSecondary.opacity(0.55))
                }
                .font(.system(size: max(13, appState.fontSize - 1)))
                .foregroundStyle(STTheme.inkSecondary)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14)
                .padding(.trailing, 12)

                Text(appState.currentTranslatedText.isEmpty ? "…" : appState.currentTranslatedText)
                    .font(STTheme.displayFont(size: max(14, appState.fontSize), weight: .semibold))
                    .foregroundStyle(appState.currentTranslatedText.isEmpty ? STTheme.inkTertiary : STTheme.ink)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 14)
            }
        }
        .frame(minHeight: 72)
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
                .font(STTheme.monoFont(size: 10, weight: .semibold))
                .foregroundStyle(STTheme.green)
                .frame(width: 64, alignment: .leading)

            HStack(spacing: 8) {
                Circle()
                    .fill(STTheme.green)
                    .frame(width: 6, height: 6)
                    .modifier(PulseModifier())
                Text("次の発話を待っています…")
                    .font(STTheme.displayFont(size: 18, weight: .regular))
                    .italic()
                    .foregroundStyle(STTheme.inkSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(spacing: 16) {
            WaveformPlaceholder()
                .foregroundStyle(STTheme.inkTertiary)

            Text("次の発話を待っています…")
                .font(STTheme.displayFont(size: 24, weight: .regular))
                .italic()
                .foregroundStyle(STTheme.inkSecondary)

            Text("SimulTrans はこの Mac 上で動作します")
                .font(STTheme.monoFont(size: 11))
                .tracking(1)
                .foregroundStyle(STTheme.inkTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
        .padding(.vertical, 28)
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
}

private struct PulseModifier: ViewModifier {
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .opacity(pulse ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}

private struct WaveformPlaceholder: View {
    private let heights: [CGFloat] = [0.22, 0.56, 0.34, 0.78, 0.40, 0.62, 0.28, 0.84, 0.46, 0.58, 0.26, 0.72, 0.36, 0.54]

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(Array(heights.enumerated()), id: \.offset) { _, value in
                Capsule()
                    .fill(STTheme.inkTertiary)
                    .frame(width: 3, height: 42 * value)
            }
        }
        .frame(height: 42)
    }
}
