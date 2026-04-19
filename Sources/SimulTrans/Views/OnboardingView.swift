import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    let permissions: PermissionManager
    var onContinue: () -> Void
    var onSkip: () -> Void

    var body: some View {
        ZStack {
            STTheme.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                topBar

                masthead
                    .padding(.horizontal, 32)
                    .padding(.top, 30)
                    .padding(.bottom, 22)

                VStack(spacing: 10) {
                    permissionCard(
                        number: "01",
                        titleKey: "Screen recording",
                        subKey: "Needed to capture system audio from meetings, webinars, and livestreams.",
                        status: permissions.screenRecording,
                        onGrant: permissions.requestScreenRecording
                    )
                    permissionCard(
                        number: "02",
                        titleKey: "Microphone",
                        subKey: "Optional. Only if you plan to translate a live conversation in the room.",
                        status: permissions.microphone,
                        onGrant: permissions.requestMicrophone
                    )
                    permissionCard(
                        number: "03",
                        titleKey: "Speech recognition",
                        subKey: "Apple's on-device speech engine powers transcription.",
                        status: permissions.speechRecognition,
                        onGrant: permissions.requestSpeechRecognition
                    )
                }
                .padding(.horizontal, 32)

                Spacer(minLength: 0)

                footerBar
            }
        }
        .frame(width: 560, height: 520)
        .preferredColorScheme(appState.appearancePreference.colorScheme)
        .environment(\.locale, appState.appInterfaceLocale)
        .onAppear { permissions.refresh() }
    }

    private var topBar: some View {
        HStack {
            Text("Step 02 / 03 · Permissions", bundle: .module)
                .font(STTheme.monoFont(size: 10))
                .tracking(2)
                .foregroundStyle(STTheme.inkTertiary)
                .textCase(.uppercase)

            Spacer()

            Text("— SimulTrans —", bundle: .module)
                .font(STTheme.monoFont(size: 10))
                .tracking(2)
                .foregroundStyle(STTheme.inkTertiary)
                .textCase(.uppercase)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            Rectangle().fill(STTheme.rule).frame(height: 1)
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("We need a little\naccess before we begin.", bundle: .module)
                .font(STTheme.displayFont(size: 36, weight: .medium))
            .tracking(-1.2)
            .lineSpacing(2)
            .foregroundStyle(STTheme.ink)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)

            Text("SimulTrans runs entirely on this device. These permissions stay between you and macOS — nothing is sent anywhere.", bundle: .module)
                .font(STTheme.bodyFont(size: 13))
                .foregroundStyle(STTheme.inkSecondary)
                .lineSpacing(3)
                .frame(maxWidth: 440, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func permissionCard(number: String,
                                titleKey: LocalizedStringKey,
                                subKey: LocalizedStringKey,
                                status: PermissionManager.Status,
                                onGrant: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Text(number)
                .font(STTheme.monoFont(size: 10))
                .tracking(1)
                .foregroundStyle(STTheme.inkTertiary)
                .frame(width: 24, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey, bundle: .module)
                    .font(STTheme.displayFont(size: 17, weight: .medium))
                    .tracking(-0.3)
                    .foregroundStyle(STTheme.ink)

                Text(subKey, bundle: .module)
                    .font(STTheme.bodyFont(size: 12))
                    .foregroundStyle(STTheme.inkSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            statusChip(status: status, onGrant: onGrant)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(STTheme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(STTheme.rule, lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func statusChip(status: PermissionManager.Status,
                            onGrant: @escaping () -> Void) -> some View {
        switch status {
        case .granted:
            HStack(spacing: 6) {
                Circle().fill(STTheme.green).frame(width: 6, height: 6)
                Text("Granted", bundle: .module)
                    .font(STTheme.monoFont(size: 10))
                    .tracking(1.5)
                    .foregroundStyle(STTheme.green)
                    .textCase(.uppercase)
            }
        case .denied:
            Button(action: openPrivacySettings) {
                Text("Open Settings", bundle: .module)
                    .font(STTheme.monoFont(size: 10))
                    .tracking(1.5)
                    .foregroundStyle(STTheme.ink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(STTheme.ruleHard, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        case .notDetermined:
            Button(action: onGrant) {
                Text("Grant", bundle: .module)
                    .font(STTheme.monoFont(size: 10))
                    .tracking(1.5)
                    .foregroundStyle(STTheme.bg)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 3).fill(STTheme.ink))
            }
            .buttonStyle(.plain)
        }
    }

    private var footerBar: some View {
        HStack {
            Button(action: onSkip) {
                Text("Skip for now", bundle: .module)
                    .font(STTheme.monoFont(size: 11))
                    .tracking(1)
                    .foregroundStyle(STTheme.inkTertiary)
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: onContinue) {
                Text("Continue →", bundle: .module)
                    .font(STTheme.monoFont(size: 12))
                    .tracking(2)
                    .foregroundStyle(STTheme.onAccent)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 4).fill(STTheme.accent))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 16)
        .background(STTheme.panel)
        .overlay(alignment: .top) {
            Rectangle().fill(STTheme.rule).frame(height: 1)
        }
    }

    private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }
}
