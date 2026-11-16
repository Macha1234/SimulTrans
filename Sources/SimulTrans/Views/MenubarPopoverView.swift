import SwiftUI

/// Fast daily control surface: one status, one route and one primary action.
struct MenubarPopoverView: View {
    @Environment(AppState.self) private var appState
    var onToggle: () -> Void
    var onToggleOverlay: () -> Void
    var onOpenWindow: () -> Void

    var body: some View {
        ZStack {
            STWindowBackdrop()

            VStack(spacing: 0) {
                header

                VStack(spacing: 12) {
                    routeCard
                    latestCaption
                }
                .padding(14)

                Spacer(minLength: 0)
                actionArea
            }
        }
        .frame(width: 360, height: 410)
        .preferredColorScheme(appState.appearancePreference.colorScheme)
        .environment(\.locale, appState.appInterfaceLocale)
    }

    private var header: some View {
        HStack(spacing: 10) {
            STBrandMark(compact: true)

            Spacer()

            HStack(spacing: 6) {
                Circle()
                    .fill(appState.isRunning ? STTheme.liveStatus : STTheme.tertiaryLabel)
                    .frame(width: 6, height: 6)
                Text(statusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(STTheme.secondaryLabel)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(appState.isRunning ? STTheme.liveStatus.opacity(0.10) : STTheme.controlBackground))
        }
        .padding(.horizontal, 18)
        .padding(.top, 17)
        .padding(.bottom, 3)
    }

    private var routeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(appState.localizedAppString("Current route"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(STTheme.secondaryLabel)
                    Text("\(languageName(for: appState.sourceLanguage))  →  \(languageName(for: appState.targetLanguage))")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(STTheme.primaryLabel)
                        .lineLimit(1)
                }

                Spacer()

                if appState.isRunning, appState.sessionStartedAt != nil {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(AppState.formatElapsed(from: appState.sessionStartedAt, now: context.date))
                            .font(STTheme.monoFont(size: 12))
                            .foregroundStyle(STTheme.liveStatus)
                    }
                }
            }

            Rectangle().fill(STTheme.separator).frame(height: 1)

            HStack(spacing: 8) {
                detailChip(icon: appState.audioSource == .system ? "speaker.wave.2" : "mic",
                           text: appState.audioSource.localizedName(in: appState.appInterfaceLocale))
                detailChip(icon: appState.recognitionEngine == .qwen3ASR1_7B ? "desktopcomputer" : "laptopcomputer",
                           text: appState.recognitionEngine.shortLabel)
                detailChip(icon: appState.overlayVisible ? "eye" : "eye.slash",
                           text: appState.overlayVisible
                           ? appState.localizedAppString("Visible")
                           : appState.localizedAppString("Hidden"))
            }
        }
        .padding(14)
        .background(STGlassSurface(accented: true))
    }

    @ViewBuilder
    private var latestCaption: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(appState.localizedAppString("Latest caption"))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(STTheme.tertiaryLabel)
                Spacer()
                if appState.isRunning {
                    MiniWaveform(active: true)
                }
            }

            if let caption = latestTranslation, !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(STTheme.primaryLabel)
                    .lineLimit(3)
            } else {
                Text(appState.isRunning
                     ? appState.localizedAppString("Listening for speech…")
                     : appState.localizedAppString("Start a session to see live captions here."))
                    .font(.system(size: 13))
                    .foregroundStyle(STTheme.tertiaryLabel)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .topLeading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
        .background(STGlassSurface())
    }

    private var actionArea: some View {
        VStack(spacing: 8) {
            Button(action: onToggle) {
                Label(primaryActionLabel,
                      systemImage: appState.isRunning ? "stop.fill" : "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(STButtonStyle(appState.isRunning ? .destructive : .primary))

            HStack(spacing: 4) {
                Button(action: onToggleOverlay) {
                    Label(appState.overlayVisible
                          ? appState.localizedAppString("Hide captions")
                          : appState.localizedAppString("Show captions"),
                          systemImage: appState.overlayVisible ? "eye.slash" : "eye")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(STButtonStyle(.quiet, compact: true))

                Button(action: onOpenWindow) {
                    Label(appState.localizedAppString("Open Control Center"), systemImage: "arrow.up.right.square")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(STButtonStyle(.quiet, compact: true))
            }
            .font(.system(size: 10, weight: .medium))
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }

    private func detailChip(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(STTheme.secondaryLabel)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(Capsule().fill(STTheme.controlBackground))
    }

    private var latestTranslation: String? {
        if !appState.currentTranslatedText.isEmpty { return appState.currentTranslatedText }
        return appState.transcriptEntries.last?.translatedText
    }

    private var statusText: String {
        switch appState.sessionPhase {
        case .starting: return appState.localizedAppString("Starting")
        case .listening: return appState.localizedAppString("Listening")
        case .transcribing: return appState.localizedAppString("Live")
        case .failed: return appState.localizedAppString("Attention")
        case .idle: return appState.localizedAppString("Ready")
        }
    }

    private var primaryActionLabel: String {
        if appState.sessionPhase == .starting { return appState.localizedAppString("Cancel startup") }
        return appState.isRunning
            ? appState.localizedAppString("Stop translation")
            : appState.localizedAppString("Start translation")
    }

    private func languageName(for selection: Locale.Language) -> String {
        AppState.localizedDisplayName(for: selection, in: appState.appInterfaceLocale)
    }
}

private struct MiniWaveform: View {
    let active: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<10, id: \.self) { index in
                Capsule()
                    .fill(active ? STTheme.liveStatus : STTheme.tertiaryLabel)
                    .frame(width: 2, height: pattern[index])
            }
        }
        .frame(height: 20)
    }

    private let pattern: [CGFloat] = [5, 12, 8, 17, 10, 20, 9, 15, 7, 11]
}
