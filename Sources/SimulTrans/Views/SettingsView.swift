import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        Form {
            Section("言語設定") {
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
            }

            Section("表示") {
                Slider(value: $appState.overlayOpacity, in: 0.3...1.0, step: 0.05) {
                    Text("不透明度")
                }

                Slider(value: $appState.fontSize, in: 12...28, step: 1) {
                    Text("文字サイズ: \(Int(appState.fontSize))")
                }
            }

            Section("使い方") {
                Text("1. 音声入力と翻訳先の言語を選びます")
                    .font(.callout)
                Text("2. 初回起動時に必要な権限を macOS で許可します")
                    .font(.callout)
                Text("3. 「翻訳を開始」を押すと字幕と翻訳がリアルタイムで表示されます")
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 420)
        .onChange(of: appState.sourceLanguage) {
            appState.updateTranslationConfig()
        }
        .onChange(of: appState.targetLanguage) {
            appState.updateTranslationConfig()
        }
    }
}
