import SwiftUI
import Translation

/// A video-first caption surface. The TranslationSession stays attached to this
/// root view while users switch between compact and transcript layouts.
struct OverlayContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var onExport: (() -> Void)?
    var onHide: (() -> Void)?
    var onTranslationReady: (() -> Void)?


    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var body: some View {
        @Bindable var appState = appState

        ZStack {
            glassBackground
                .ignoresSafeArea()

            captionHistory
                .padding(.top, 44)

            overlayChrome
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .preferredColorScheme(.dark)
        .environment(\.locale, appState.overlayInterfaceLocale)
        .translationTask(appState.translationConfig) { session in
            appState.translationSession = session
            onTranslationReady?()
        }
    }

    private var glassBackground: some View {
        ZStack {
            if reduceTransparency {
                STTheme.overlayBackground
            } else {
                STVisualEffectMaterial(material: .hudWindow)
                    .opacity(panelOpacity)
            }

            STTheme.overlayBackground.opacity(panelOpacity * 0.12)

            LinearGradient(
                colors: [.white.opacity(0.10), .white.opacity(0.025), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.28), .white.opacity(0.07), .white.opacity(0.14)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.75
                )
        }
        .allowsHitTesting(false)
    }

    // All layouts share the same retained history and scroll policy.
    private var captionHistory: some View {
        CaptionHistoryScrollView(
            content: AnyView(historyRows),
            followsLatest: appState.captionScroll.followsLatest,
            onUserScroll: { appState.captionScroll.userDidScroll() }
        )
        .overlay(alignment: .bottomTrailing) {
            if !appState.captionScroll.followsLatest {
                Button {
                    appState.captionScroll.resume()
                } label: {
                    Label(appState.localizedOverlayString("Back to latest"), systemImage: "arrow.down.to.line")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.regularMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(12)
                .accessibilityIdentifier("caption-back-to-latest")
            }
        }
    }

    private var historyRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appState.transcriptEntries.isEmpty && appState.currentOriginalText.isEmpty {
                listeningPlaceholder.padding(22)
            }
            ForEach(appState.transcriptEntries) { entry in
                captionRow(source: entry.originalText, translation: entry.translatedText,
                           timestamp: entry.timestamp, live: false)
            }
            if !appState.currentOriginalText.isEmpty {
                captionRow(source: appState.currentOriginalText,
                           translation: appState.currentTranslatedText.isEmpty ? nil : appState.currentTranslatedText,
                           timestamp: nil, live: true)
            }
        }
        .textSelection(.enabled)
    }

    private func captionRow(source: String, translation: String?, timestamp: Date?, live: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if appState.overlayLayoutMode == .transcript {
                Text(timestamp.map(timeFormatter.string(from:)) ?? "•••")
                    .font(STTheme.monoFont(size: 10))
                    .foregroundStyle(STTheme.overlayTertiary)
                    .frame(width: 52, alignment: .leading)
                    .padding(.top, 4)
            }
            VStack(alignment: .leading, spacing: 6) {
                if appState.overlayLayoutMode != .subtitles {
                    Text(source)
                        .font(.system(size: max(14, appState.fontSize * 0.65)))
                        .foregroundStyle(STTheme.overlaySecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(translation ?? appState.localizedOverlayString("Translating…"))
                    .font(.system(size: appState.fontSize, weight: .semibold))
                    .foregroundStyle(translation == nil ? STTheme.overlayTertiary : STTheme.overlayPrimary)
                    .lineSpacing(3)
                    .shadow(color: .black.opacity(0.30), radius: 2, y: 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 24).padding(.vertical, 18)
        .background(live ? STTheme.liveStatus.opacity(0.06) : .clear)
        .overlay(alignment: .bottom) { Rectangle().fill(STTheme.overlayRule).frame(height: 1) }
    }

    private var listeningPlaceholder: some View {
        HStack(spacing: 12) {
            CompactWaveform(active: appState.isRunning)

            VStack(alignment: .leading, spacing: 2) {
                Text(appState.isRunning
                     ? appState.localizedOverlayString("Listening for speech…")
                     : appState.localizedOverlayString("Ready when you are"))
                    .font(.system(size: max(16, appState.fontSize * 0.76), weight: .semibold))
                    .foregroundStyle(STTheme.overlaySecondary)

                Text("\(languageCode(for: appState.sourceLanguage)) → \(languageCode(for: appState.targetLanguage))")
                    .font(STTheme.monoFont(size: 10))
                    .foregroundStyle(STTheme.overlayTertiary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 140, alignment: .leading)
    }

    // MARK: - Persistent toolbar

    private var overlayChrome: some View {
        VStack {
            HStack(spacing: 9) {
                Circle()
                    .fill(appState.isRunning ? STTheme.liveStatus : STTheme.overlayTertiary)
                    .frame(width: 6, height: 6)

                Text(appState.isRunning
                     ? appState.localizedOverlayString("Live")
                     : appState.localizedOverlayString("Ready"))
                    .font(STTheme.bodyFont(size: 11, weight: .semibold))
                    .foregroundStyle(STTheme.overlaySecondary)

                Text("\(languageCode(for: appState.sourceLanguage)) → \(languageCode(for: appState.targetLanguage))")
                    .font(STTheme.monoFont(size: 10, weight: .regular))
                    .foregroundStyle(STTheme.overlayTertiary)

                Spacer()

                Group {
                    ForEach(AppState.OverlayLayoutMode.allCases) { mode in
                        Button {
                            appState.overlayLayoutMode = mode
                        } label: {
                            Image(systemName: icon(for: mode))
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(mode == appState.overlayLayoutMode
                                                 ? STTheme.overlayPrimary
                                                 : STTheme.overlayTertiary)
                                .frame(width: 30, height: 30)
                                .background(RoundedRectangle(cornerRadius: 9).fill(mode == appState.overlayLayoutMode
                                                          ? Color.white.opacity(0.14)
                                                          : Color.clear))
                        }
                        .buttonStyle(.plain)
                        .help(appState.localizedOverlayString(mode.localizationKey))
                        .accessibilityLabel(appState.localizedOverlayString(mode.localizationKey))
                        .accessibilityAddTraits(mode == appState.overlayLayoutMode ? .isSelected : [])
                    }

                    if !appState.transcriptEntries.isEmpty {
                        Button(action: { onExport?() }) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(STTheme.overlaySecondary)
                                .frame(width: 30, height: 30)
                        }
                        .buttonStyle(.plain)
                        .help(appState.localizedOverlayString("Export transcript"))
                        .accessibilityLabel(appState.localizedOverlayString("Export transcript"))
                    }

                    Button(action: { onHide?() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(STTheme.overlaySecondary)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                    .help(appState.localizedOverlayString("Hide captions"))
                    .accessibilityLabel(appState.localizedOverlayString("Hide captions"))
                }
            }
            .padding(.horizontal, 18)
            .frame(height: 44)
            .background(Color.white.opacity(0.035))
            .overlay(alignment: .bottom) {
                Rectangle().fill(STTheme.overlayRule).frame(height: 1)
            }

            Spacer()
        }

    }

    private var panelOpacity: Double {
        min(max(appState.overlayOpacity, 0.35), 1)
    }

    private func icon(for mode: AppState.OverlayLayoutMode) -> String {
        switch mode {
        case .subtitles: return "captions.bubble"
        case .bilingual: return "text.bubble"
        case .transcript: return "list.bullet.rectangle"
        }
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
        return selection.minimalIdentifier.prefix(2).uppercased()
    }
}

private struct CompactWaveform: View {
    let active: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<10, id: \.self) { index in
                Capsule()
                    .fill(active ? STTheme.liveStatus : STTheme.overlayTertiary)
                    .frame(width: 3, height: pattern[index])
            }
        }
        .frame(height: 30)
    }

    private let pattern: [CGFloat] = [7, 15, 10, 24, 17, 28, 13, 21, 9, 16]
}
