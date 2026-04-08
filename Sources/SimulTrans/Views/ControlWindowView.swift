import SwiftUI

struct ControlWindowView: View {
    @Bindable var appState: AppState
    var onStart: () -> Void
    var onStop: () -> Void
    var onExport: () -> Void
    var onClear: () -> Void

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
                Picker("音声入力", selection: $appState.audioSource) {
                    ForEach(AppState.AudioSource.allCases, id: \.self) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(appState.isRunning)

                Picker("音声の言語", selection: $appState.sourceLanguage) {
                    ForEach(AppState.supportedLanguages) { language in
                        Text(language.name).tag(language.locale)
                    }
                }

                Picker("翻訳先", selection: $appState.targetLanguage) {
                    ForEach(AppState.supportedLanguages) { language in
                        Text(language.name).tag(language.locale)
                    }
                }

                Slider(value: $appState.overlayOpacity, in: 0.3...1.0, step: 0.05) {
                    Text("不透明度")
                }

                Slider(value: $appState.fontSize, in: 12...28, step: 1) {
                    Text("文字サイズ: \(Int(appState.fontSize))")
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
                    Text(appState.isRunning ? "翻訳を停止" : "翻訳を開始")
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
                            Text("書き出す")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.bordered)

                    Button(action: onClear) {
                        HStack {
                            Image(systemName: "trash")
                            Text("履歴を消去")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .padding(.horizontal)

                Text("\(appState.transcriptEntries.count) 件の履歴")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Instructions
            if !appState.isRunning && appState.transcriptEntries.isEmpty {
                Text(appState.audioSource == .system
                     ? "システム音声を翻訳するには、初回起動時に画面収録の許可が必要です"
                     : "マイク音声を翻訳するには、初回起動時にマイクへのアクセス許可が必要です")
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
