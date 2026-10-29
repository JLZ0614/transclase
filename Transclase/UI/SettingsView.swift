import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

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
                    Toggle("实时草稿翻译", isOn: $model.settings.draftTranslation)
                        .disabled(model.isRunning)
                    Toggle("演示模式", isOn: $model.settings.demoMode)
                        .disabled(model.isRunning)
                } header: {
                    Text("行为")
                } footer: {
                    Text("实时草稿会在句子没说完时先给一版半透明译文，句子结束后替换成正式译文。只翻整句更准，但会晚 1–2 秒。")
                }

                Section("术语") {
                    NavigationLink {
                        GlossaryEditor()
                            .environmentObject(model)
                    } label: {
                        HStack {
                            Label("课程术语表", systemImage: "character.book.closed")
                            Spacer()
                            Text("\(model.settings.glossary.count) 条")
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
            .navigationTitle("设置")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 600)
        #endif
    }
}

struct GlossaryEditor: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Section {
                ForEach($model.settings.glossary) { $term in
                    HStack(spacing: 8) {
                        TextField("原文术语", text: $term.source)
                            .textFieldStyle(.roundedBorder)
                        Image(systemName: "arrow.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        TextField("译法", text: $term.target)
                            .textFieldStyle(.roundedBorder)
                        // Swipe-to-delete only exists on iOS, so macOS needs an
                        // explicit control.
                        Button {
                            model.settings.glossary.removeAll { $0.id == term.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("删除这条术语")
                    }
                }
                .onDelete { offsets in
                    model.settings.glossary.remove(atOffsets: offsets)
                }
            } footer: {
                Text("术语表用于纠正模型把专有名词、缩写原样留下的情况。同一个词在一节课里保持同一种译法，比偶尔译得更漂亮更重要。")
            }
        }
        .navigationTitle("术语表")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.settings.glossary.append(GlossaryTerm(source: "", target: ""))
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
}
