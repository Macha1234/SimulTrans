import SwiftUI

struct MenubarPopoverView: View {
    @Environment(AppState.self) private var appState
    var onToggle: () -> Void
    var onOpenWindow: () -> Void

    var body: some View {
        ZStack {
            STTheme.bg

            VStack(alignment: .leading, spacing: 0) {
                header
                Rectangle().fill(STTheme.rule).frame(height: 1)
                summary
                Spacer(minLength: 0)
                footer
            }
        }
        .frame(width: 320, height: 360)
        .preferredColorScheme(appState.appearancePreference.colorScheme)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(appState.isRunning ? STTheme.green : STTheme.inkTertiary)
                    .frame(width: 8, height: 8)

                Text(appState.isRunning ? "ON AIR" : "STANDBY", bundle: .module)
                    .font(STTheme.monoFont(size: 10))
                    .tracking(2)
                    .foregroundStyle(STTheme.inkSecondary)

                Spacer()

                MiniWaveform(active: appState.isRunning)
            }

            if appState.isRunning, appState.sessionStartedAt != nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(AppState.formatElapsed(from: appState.sessionStartedAt, now: context.date))
                        .font(STTheme.displayFont(size: 26, weight: .medium))
                        .tracking(-0.6)
                        .foregroundStyle(STTheme.ink)
                }
            } else {
                Text("00:00")
                    .font(STTheme.displayFont(size: 26, weight: .medium))
                    .tracking(-0.6)
                    .foregroundStyle(STTheme.inkTertiary)
            }

            Text("\(appState.transcriptEntries.count) entries · \(routeLabel)", bundle: .module)
                .font(STTheme.monoFont(size: 10))
                .tracking(1)
                .foregroundStyle(STTheme.inkTertiary)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var summary: some View {
        VStack(spacing: 0) {
            row(labelKey: "Source", value: languageName(for: appState.sourceLanguage))
            row(labelKey: "Target", value: languageName(for: appState.targetLanguage))
            row(labelKey: "Input",  value: appState.audioSource.localizedName)
            row(labelKey: "Overlay",
                value: String(localized: appState.isRunning ? "Visible" : "Hidden", bundle: .module),
                emphasised: appState.isRunning)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private func row(labelKey: LocalizedStringKey, value: String, emphasised: Bool = false) -> some View {
        HStack {
            Text(labelKey, bundle: .module)
                .font(STTheme.monoFont(size: 10))
                .tracking(1.5)
                .foregroundStyle(STTheme.inkTertiary)
                .textCase(.uppercase)

            Spacer()

            Text(value)
                .font(STTheme.bodyFont(size: 13, weight: .medium))
                .foregroundStyle(emphasised ? STTheme.accent : STTheme.ink)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 7)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button(action: onToggle) {
                Text(appState.isRunning ? "STOP" : "START", bundle: .module)
                    .font(STTheme.monoFont(size: 11))
                    .tracking(1.6)
                    .foregroundStyle(STTheme.onAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 4).fill(STTheme.accent))
            }
            .buttonStyle(.plain)

            Button(action: onOpenWindow) {
                Text("OPEN WINDOW", bundle: .module)
                    .font(STTheme.monoFont(size: 10))
                    .tracking(1.5)
                    .foregroundStyle(STTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(STTheme.ruleHard, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(STTheme.panel)
        .overlay(alignment: .top) {
            Rectangle().fill(STTheme.rule).frame(height: 1)
        }
    }

    // MARK: - Helpers

    private var routeLabel: String {
        "\(languageCode(for: appState.sourceLanguage)) → \(languageCode(for: appState.targetLanguage))"
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
        let id = selection.minimalIdentifier.lowercased()
        if id.hasPrefix("zh") { return "ZH" }
        if id.hasPrefix("ja") { return "JA" }
        if id.hasPrefix("ko") { return "KO" }
        if id.hasPrefix("en") { return "EN" }
        if id.hasPrefix("pt") { return "PT" }
        if id.hasPrefix("es") { return "ES" }
        if id.hasPrefix("fr") { return "FR" }
        if id.hasPrefix("de") { return "DE" }
        if id.hasPrefix("it") { return "IT" }
        if id.hasPrefix("ru") { return "RU" }
        if id.hasPrefix("ar") { return "AR" }
        return selection.minimalIdentifier.prefix(2).uppercased()
    }
}

private struct MiniWaveform: View {
    let active: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<10, id: \.self) { index in
                Capsule()
                    .fill(active ? STTheme.accent : STTheme.inkTertiary.opacity(0.5))
                    .frame(width: 2, height: heightFor(index: index))
            }
        }
        .frame(height: 22)
    }

    private func heightFor(index: Int) -> CGFloat {
        let pattern: [CGFloat] = [6, 14, 9, 18, 12, 22, 10, 16, 8, 13]
        return pattern[index % pattern.count]
    }
}
