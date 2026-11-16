import SwiftUI

struct OnboardingView: View {
    @Environment(AppState.self) private var appState
    let permissions: PermissionManager
    var onContinue: () -> Void
    var onSkip: () -> Void

    var body: some View {
        ZStack {
            STWindowBackdrop()

            VStack(spacing: 0) {
                topBar

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        masthead

                        VStack(spacing: 12) {
                            permissionCard(
                                icon: "rectangle.inset.filled.and.person.filled",
                                titleKey: "Screen recording",
                                subKey: "Needed to capture system audio from meetings, webinars, and livestreams.",
                                status: permissions.screenRecording,
                                onGrant: permissions.requestScreenRecording
                            )
                            permissionCard(
                                icon: "mic.fill",
                                titleKey: "Microphone",
                                subKey: "Optional. Only if you plan to translate a live conversation in the room.",
                                status: permissions.microphone,
                                onGrant: permissions.requestMicrophone
                            )
                            permissionCard(
                                icon: "waveform",
                                titleKey: "Speech recognition",
                                subKey: "Apple's on-device speech engine powers transcription.",
                                status: permissions.speechRecognition,
                                onGrant: permissions.requestSpeechRecognition
                            )
                        }
                    }
                    .padding(.horizontal, 30)
                    .padding(.top, 24)
                    .padding(.bottom, 24)
                }

                footerBar
            }
        }
        .frame(minWidth: 600, minHeight: 600)
        .preferredColorScheme(appState.appearancePreference.colorScheme)
        .environment(\.locale, appState.appInterfaceLocale)
        .onAppear { permissions.refresh() }
    }

    private var topBar: some View {
        HStack {
            STBrandMark(compact: true)

            Spacer()

            Label {
                Text("Permissions", bundle: .module)
            } icon: {
                Image(systemName: "lock.shield")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(STTheme.secondaryLabel)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 20)
        .overlay(alignment: .bottom) {
            Rectangle().fill(STTheme.separator).frame(height: 1)
        }
    }

    private var masthead: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("We need a little\naccess before we begin.", bundle: .module)
                .font(STTheme.displayFont(size: 30, weight: .semibold))
                .tracking(-0.7)
                .foregroundStyle(STTheme.primaryLabel)
                .fixedSize(horizontal: false, vertical: true)

            Text("Choose the permissions for your audio source. You can change access at any time in System Settings.", bundle: .module)
                .font(STTheme.bodyFont(size: 13))
                .foregroundStyle(STTheme.secondaryLabel)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func permissionCard(icon: String,
                                titleKey: LocalizedStringKey,
                                subKey: LocalizedStringKey,
                                status: PermissionManager.Status,
                                onGrant: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 14) {
            STIconBadge(systemName: icon, size: 38)

            VStack(alignment: .leading, spacing: 7) {
                Text(titleKey, bundle: .module)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(STTheme.primaryLabel)

                Text(subKey, bundle: .module)
                    .font(STTheme.bodyFont(size: 12))
                    .foregroundStyle(STTheme.secondaryLabel)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                statusChip(status: status, onGrant: onGrant)
                    .padding(.top, 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(STGlassSurface())
    }

    @ViewBuilder
    private func statusChip(status: PermissionManager.Status,
                            onGrant: @escaping () -> Void) -> some View {
        switch status {
        case .granted:
            Label {
                Text("Granted", bundle: .module)
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(STTheme.liveStatus)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(STTheme.liveStatus.opacity(0.10)))
        case .denied:
            Button(action: openPrivacySettings) {
                Label {
                    Text("Open Settings", bundle: .module)
                } icon: {
                    Image(systemName: "arrow.up.right")
                }
            }
            .buttonStyle(STButtonStyle(.secondary, compact: true))
        case .notDetermined:
            Button(action: onGrant) {
                Text("Grant", bundle: .module)
            }
            .buttonStyle(STButtonStyle(.primary, compact: true))
        }
    }

    private var footerBar: some View {
        HStack(spacing: 16) {
            Button(action: onSkip) {
                Text("Skip for now", bundle: .module)
            }
            .buttonStyle(STButtonStyle(.quiet))

            Spacer()

            Button(action: onContinue) {
                Text("Continue →", bundle: .module)
                    .frame(minWidth: 110)
            }
            .buttonStyle(STButtonStyle(.primary))
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 18)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(STTheme.separator).frame(height: 1)
        }
    }

    private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") {
            NSWorkspace.shared.open(url)
        }
    }
}
