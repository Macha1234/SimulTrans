import SwiftUI

struct ControlWindowView: View {
    @Bindable var appState: AppState
    var onStart: () -> Void
    var onStop: () -> Void
    var onExport: () -> Void
    var onClear: () -> Void

    private let supportedLanguages: [(String, Locale.Language)] = [
        ("English (US)", .init(identifier: "en-US")),
        ("English (UK)", .init(identifier: "en-GB")),
        ("简体中文", .init(identifier: "zh-Hans")),
        ("繁體中文", .init(identifier: "zh-Hant")),
        ("日本語", .init(identifier: "ja")),
        ("한국어", .init(identifier: "ko")),
        ("Español", .init(identifier: "es")),
        ("Français", .init(identifier: "fr")),
        ("Deutsch", .init(identifier: "de")),
        ("Português", .init(identifier: "pt-BR")),
        ("Italiano", .init(identifier: "it")),
        ("Русский", .init(identifier: "ru")),
        ("العربية", .init(identifier: "ar")),
    ]

    var body: some View {
        VStack(spacing: 16) {
            // Title
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .font(.title)
                    .foregroundStyle(.blue)
                Text("SimulTrans")
                    .font(.title2.bold())
            }

            // Language settings
            Form {
                Picker("音频来源", selection: $appState.audioSource) {
                    ForEach(AppState.AudioSource.allCases, id: \.self) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(appState.isRunning)

                Picker("源语言", selection: $appState.sourceLanguage) {
                    ForEach(supportedLanguages, id: \.1.minimalIdentifier) { name, lang in
                        Text(name).tag(lang)
                    }
                }

                Picker("目标语言", selection: $appState.targetLanguage) {
                    ForEach(supportedLanguages, id: \.1.minimalIdentifier) { name, lang in
                        Text(name).tag(lang)
                    }
                }

                Slider(value: $appState.overlayOpacity, in: 0.3...1.0, step: 0.05) {
                    Text("透明度")
                }

                Slider(value: $appState.fontSize, in: 12...28, step: 1) {
                    Text("字号: \(Int(appState.fontSize))")
                }
            }
            .formStyle(.grouped)

            // Error message
            if let error = appState.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            // Start/Stop button
            Button(action: {
                if appState.isRunning {
                    onStop()
                } else {
                    onStart()
                }
            }) {
                HStack {
                    Image(systemName: appState.isRunning ? "stop.fill" : "play.fill")
                    Text(appState.isRunning ? "停止同传" : "开始同传")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .tint(appState.isRunning ? .red : .blue)
            .padding(.horizontal)

            // Export & Clear buttons
            if !appState.transcriptEntries.isEmpty {
                HStack(spacing: 12) {
                    Button(action: onExport) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                            Text("保存记录")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.bordered)

                    Button(action: onClear) {
                        HStack {
                            Image(systemName: "trash")
                            Text("清空记录")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding(.horizontal)

                Text("共 \(appState.transcriptEntries.count) 条记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Instructions
            if !appState.isRunning && appState.transcriptEntries.isEmpty {
                Text(appState.audioSource == .system
                     ? "捕获系统音频并实时翻译，需要授权屏幕录制权限"
                     : "捕获麦克风音频并实时翻译，需要授权麦克风权限")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        .padding()
        .frame(width: 380)
    }
}
