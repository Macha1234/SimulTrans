import SwiftUI

struct ControlWindowView: View {
    @Bindable var appState: AppState
    var onStart: () -> Void
    var onStop: () -> Void
    var onExport: () -> Void
    var onClear: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "waveform.circle.fill")
                        .font(.title)
                        .foregroundStyle(.blue)
                    Text("SimulTrans")
                        .font(.title2.bold())
                }

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

                if let error = appState.errorMessage {
                    Text(error)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

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

                debugPanel

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
        }
        .frame(width: 440, height: 700)
    }

    private var debugPanel: some View {
        DisclosureGroup(isExpanded: $appState.debugPanelExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Label(appState.recognitionPhase.capitalized, systemImage: "waveform.path.ecg")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("raw \(appState.rawRecognitionText.count)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                }

                debugTextBlock(title: "Raw recognizer text", text: appState.rawRecognitionText)
                debugTextBlock(title: "Effective text after processing", text: appState.effectiveRecognitionText)
                debugTextBlock(title: "Displayed live text", text: appState.currentOriginalText)
                debugTextBlock(title: "Current translation", text: appState.currentTranslatedText)
                debugTextBlock(title: "Last final recognizer text", text: appState.lastFinalRecognitionText)

                if !appState.debugRecognitionEntries.isEmpty {
                    Divider()

                    Text("Recent recognition updates")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(appState.debugRecognitionEntries) { entry in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(entry.phase.uppercased())
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(entry.phase == "final" ? .green : .orange)

                                    Spacer()

                                    Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.tertiary)
                                }

                                debugSnapshotRow(title: "raw", text: entry.rawText)
                                debugSnapshotRow(title: "effective", text: entry.effectiveText)
                                debugSnapshotRow(title: "shown", text: entry.displayedText)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                        }
                    }
                }
            }
            .padding(.top, 8)
        } label: {
            Label("Debug Recognition View", systemImage: "ladybug")
                .font(.headline)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal)
    }

    private func debugTextBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.bold())
                .foregroundStyle(.secondary)

            Text(text.isEmpty ? "No data yet" : text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(text.isEmpty ? .tertiary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private func debugSnapshotRow(title: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)

            Text(text.isEmpty ? "empty" : text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(text.isEmpty ? .tertiary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
