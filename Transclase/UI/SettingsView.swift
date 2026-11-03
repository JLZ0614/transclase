import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var cloudKey = ""

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("当前引擎") {
                        Text(model.translationEngineLabel)
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("离线语言包") {
                        Text(model.languagePackStatus)
                            .foregroundStyle(model.languagePackStatus == "已安装" ? .green : .secondary)
                    }

                    Button {
                        // The system prompt belongs to the main window; get the
                        // sheet out of the way first.
                        dismiss()
                        Task {
                            try? await Task.sleep(for: .milliseconds(350))
                            await model.downloadLanguagePack()
                        }
                    } label: {
                        Label("下载 / 刷新离线语言包", systemImage: "arrow.down.circle")
                    }
                    .disabled(model.isRunning)

                    if let note = model.translationNote {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("翻译")
                } footer: {
                    Text("优先使用系统离线翻译（质量最好）。语言包没下载时会自动退回 Apple 智能端侧模型；两者都不可用就只显示原文。也可以在 系统设置 → 通用 → 语言与地区 → 翻译语言 里手动下载。")
                }

                Section {
                    Picker("翻译引擎", selection: $model.settings.translationEngine) {
                        ForEach(TranslationEngineKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .disabled(model.isRunning)

                    Text(model.settings.translationEngine.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    switch model.settings.translationEngine {
                    case .apple:
                        EmptyView()

                    case .localQwen:
                        TextField("地址", text: $model.settings.localBaseURL)
                            .textFieldStyle(.roundedBorder)
                            .disabled(model.isRunning)
                        TextField("模型名", text: $model.settings.localModel)
                            .textFieldStyle(.roundedBorder)
                            .disabled(model.isRunning)
                        Text("先在本机跑起来：\n`ollama pull qwen3:4b` 然后 `ollama serve`\n地址默认指向 Ollama。")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)

                    case .cloud:
                        TextField("地址", text: $model.settings.cloudBaseURL)
                            .textFieldStyle(.roundedBorder)
                            .disabled(model.isRunning)
                        TextField("模型名", text: $model.settings.cloudModel)
                            .textFieldStyle(.roundedBorder)
                            .disabled(model.isRunning)
                        SecureField("API Key（存在钥匙串）", text: $cloudKey)
                            .textFieldStyle(.roundedBorder)
                            .disabled(model.isRunning)
                        Text("文字会发送到该服务商。音频仍然只在本机处理。")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if model.settings.translationEngine != .apple {
                        Button {
                            Task { await model.testTranslationEngine() }
                        } label: {
                            Label(model.isTestingEngine ? "测试中…" : "测试连接", systemImage: "bolt.horizontal")
                        }
                        .disabled(model.isRunning || model.isTestingEngine)

                        if let result = model.engineTestResult {
                            Text(result)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                } header: {
                    Text("翻译引擎")
                }

                Section {
                    Picker("识别语言", selection: $model.settings.sourceLanguageID) {
                        ForEach(model.speechOptions) { option in
                            Text(option.displayName).tag(option.id)
                        }
                    }
                    .disabled(model.isRunning)

                    Picker("翻译成", selection: $model.settings.targetLanguageID) {
                        ForEach(model.translationOptions) { option in
                            Text(option.displayName).tag(option.id)
                        }
                    }
                    .disabled(model.isRunning)
                } header: {
                    Text("语言")
                } footer: {
                    Text("列表只显示这台设备真正支持的选项：识别 \(model.speechOptions.count) 种，翻译 \(model.translationOptions.count) 种。")
                }

                Section("显示") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("译文字号")
                            Spacer()
                            Text("\(Int(model.settings.fontSize)) pt")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(value: $model.settings.fontSize, in: 16...44, step: 1)
                    }

                    Toggle("显示原文", isOn: $model.settings.showOriginal)
                    Toggle("自动跟随最新字幕", isOn: $model.settings.autoScroll)
                }

                Section {
                    Toggle("演示模式", isOn: $model.settings.demoMode)
                        .disabled(model.isRunning)
                } header: {
                    Text("行为")
                } footer: {
                    Text("译文按完整句子输出：识别到的碎片会先攒成一句，遇到句号或停顿再翻译，准确率明显高于逐片翻译。代价是最后一句会晚 1–2 秒出现。")
                }

                Section("模型") {
                    NavigationLink {
                        ModelManagerView()
                            .environmentObject(model)
                    } label: {
                        HStack {
                            Label("已下载的模型", systemImage: "internaldrive")
                            Spacer()
                            Text("\(model.speechOptions.filter(\.isInstalled).count) 个识别")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("关于") {
                    LabeledContent("版本", value: version)
                    LabeledContent("本机能力") {
                        Text("识别 \(model.speechOptions.count) · 翻译 \(model.translationOptions.count)")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Apple 智能") {
                        Text(model.isFoundationModelAvailable ? "可用" : "不可用")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("隐私") {
                    Text("音频只在本机内存中处理，不上传。识别与翻译都使用系统自带模型。录音前请确认所在学校与当地法律对课堂录音的要求。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .onAppear { cloudKey = Keychain.load("cloudAPIKey") ?? "" }
            .onChange(of: cloudKey) { _, newValue in
                model.saveCloudAPIKey(newValue)
            }
            .navigationTitle("设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 600)
    }
}
