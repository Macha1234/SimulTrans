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

        VStack(spacing: 0) {
            // Header
            HStack {
                Circle()
                    .fill(appState.isRunning ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                Text(appState.isRunning ? "同传中" : "已停止")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Spacer()

                if !appState.transcriptEntries.isEmpty {
                    Text("\(appState.transcriptEntries.count) 条")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Button(action: { onExport?() }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("保存记录")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider().opacity(0.3)

            // Transcript body
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Completed entries
                        ForEach(appState.transcriptEntries) { entry in
                            entryView(entry: entry)
                                .id(entry.id)
                        }

                        // Current live entry
                        if !appState.currentOriginalText.isEmpty {
                            liveEntryView()
                                .id("live")
                        } else if appState.isRunning {
                            listeningStateView()
                                .id("listening")
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial.opacity(appState.overlayOpacity))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .translationTask(appState.translationConfig) { session in
            appState.translationSession = session
        }
    }

    // MARK: - Completed entry

    @ViewBuilder
    private func entryView(entry: TranscriptEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            // Timestamp
            Text(timeFmt.string(from: entry.timestamp))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)

            // Original
            Text(entry.originalText)
                .font(.system(size: appState.fontSize))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            // Translation
            if let translated = entry.translatedText {
                Text(translated)
                    .font(.system(size: appState.fontSize, weight: .medium))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)

        Divider().opacity(0.15).padding(.horizontal, 12)
    }

    // MARK: - Live entry (currently being spoken)

    @ViewBuilder
    private func liveEntryView() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                // Pulsing indicator
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                    .modifier(PulseModifier())
                Text("正在识别…")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.red.opacity(0.7))
            }

            Text(appState.currentOriginalText)
                .font(.system(size: appState.fontSize))
                .foregroundStyle(.secondary)

            if !appState.currentTranslatedText.isEmpty {
                Text(appState.currentTranslatedText)
                    .font(.system(size: appState.fontSize, weight: .medium))
                    .foregroundStyle(.primary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.05))
    }

    @ViewBuilder
    private func listeningStateView() -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.green)
                .frame(width: 6, height: 6)
                .modifier(PulseModifier())
            Text("正在监听，等待下一句…")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.04))
    }
}

// MARK: - Pulse animation

private struct PulseModifier: ViewModifier {
    @State private var pulse = false
    func body(content: Content) -> some View {
        content
            .opacity(pulse ? 0.3 : 1.0)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
            .onAppear { pulse = true }
    }
}
