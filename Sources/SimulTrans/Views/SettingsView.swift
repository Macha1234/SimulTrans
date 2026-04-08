import SwiftUI

struct SettingsView: View {
    @Environment(AppState.self) private var appState

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
        @Bindable var appState = appState

        Form {
            Section("语言设置") {
                Picker("源语言 (识别语言)", selection: $appState.sourceLanguage) {
                    ForEach(supportedLanguages, id: \.1.minimalIdentifier) { name, lang in
                        Text(name).tag(lang)
                    }
                }

                Picker("目标语言 (翻译为)", selection: $appState.targetLanguage) {
                    ForEach(supportedLanguages, id: \.1.minimalIdentifier) { name, lang in
                        Text(name).tag(lang)
                    }
                }
            }

            Section("外观") {
                Slider(value: $appState.overlayOpacity, in: 0.3...1.0, step: 0.05) {
                    Text("透明度")
                }

                Slider(value: $appState.fontSize, in: 12...28, step: 1) {
                    Text("字号: \(Int(appState.fontSize))")
                }
            }

            Section("说明") {
                Text("1. 在「系统设置 → 辅助功能 → 实时字幕」中开启实时字幕")
                    .font(.callout)
                Text("2. 本应用需要「辅助功能」权限来读取实时字幕文字")
                    .font(.callout)
                Text("3. 翻译使用 Apple 本地 AI，首次使用某语言对可能需要下载语言包")
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
