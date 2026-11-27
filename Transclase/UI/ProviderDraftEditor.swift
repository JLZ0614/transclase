import SwiftUI

/// Edits a provider that does not exist in settings yet. Nothing is added until
/// the user taps 完成 — cancelling leaves no trace.
struct ProviderDraftEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft: ModelProvider
    @State private var keyDraft = ""
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var newModelName = ""

    let onSave: (ModelProvider) -> Void

    init(seed: ModelProvider, onSave: @escaping (ModelProvider) -> Void) {
        _draft = State(initialValue: seed)
        self.onSave = onSave
    }

    /// A provider without a model cannot translate anything, so它 isn't
    /// allowed to be saved.
    /// Same proportions as the settings sheet.
    private var sheetSize: CGSize {
        let window = model.windowSize
        let width = min(max(460, window.width * 0.72), min(640, window.width - 60))
        let height = min(max(360, window.height * 0.78), min(560, window.height - 90))
        return CGSize(width: width, height: height)
    }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !draft.model.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Menu {
                        ForEach(ProviderPreset.all) { preset in
                            Button(preset.name) {
                                draft.name = preset.name
                                draft.baseURL = preset.baseURL
                                draft.models = preset.models
                                draft.model = preset.models.first ?? ""
                                draft.apiKeyURL = preset.apiKeyURL
                            }
                        }
                    } label: {
                        LabeledContent(L("从预设填充"), value: draft.name.isEmpty ? L("选择厂商") : draft.name)
                    }
                }

                Section {
                    LabeledContent(L("名称")) {
                        TextField("", text: $draft.name,
                                  prompt: Text(L("必填")).foregroundStyle(.tertiary))
                            .multilineTextAlignment(.trailing)
                    }

                    LabeledContent(L("接口地址")) {
                        TextField("", text: $draft.baseURL,
                                  prompt: Text("https://api.example.com/v1").foregroundStyle(.tertiary))
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textContentType(.URL)
                    }
                } footer: {
                    Text(L("接口地址可留空，使用官方默认地址；自定义中转需填 OpenAI 兼容地址，通常以 /v1 结尾。"))
                }

                Section {
                    ForEach(draft.models, id: \.self) { name in
                        HStack {
                            Button {
                                draft.model = name
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: name == draft.model
                                          ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(name == draft.model
                                                         ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                    Text(name).foregroundStyle(.primary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            if draft.models.count > 1 {
                                Button {
                                    draft.models.removeAll { $0 == name }
                                    if draft.model == name { draft.model = draft.models.first ?? "" }
                                } label: {
                                    Image(systemName: "minus.circle")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        TextField(L("新模型名称"), text: $newModelName)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                        Button(L("添加")) {
                            let trimmed = newModelName.trimmingCharacters(in: .whitespaces)
                            guard !trimmed.isEmpty else { return }
                            if !draft.models.contains(trimmed) { draft.models.append(trimmed) }
                            if draft.model.isEmpty { draft.model = trimmed }
                            newModelName = ""
                        }
                        .buttonStyle(.borderless)
                        .disabled(newModelName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text(L("模型"))
                } footer: {
                    if draft.models.isEmpty {
                        Text(L("先添加一个模型名称，例如 gpt-4o-mini 或 deepseek-chat。"))
                    } else if draft.model.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text(L("请选择一个模型。"))
                    }
                }

                Section {
                    SecureField(L("API Key"), text: $keyDraft,
                                prompt: Text(L("粘贴供应商提供的 Key")))
                        .autocorrectionDisabled()
                        .onChange(of: keyDraft) { _, value in
                            model.saveProviderKey(draft, key: value)
                        }

                    if !draft.apiKeyURL.isEmpty, let url = URL(string: draft.apiKeyURL) {
                        Link(destination: url) {
                            Label(L("获取 API Key"), systemImage: "arrow.up.right.square")
                        }
                    }

                    Button {
                        testResult = nil
                        isTesting = true
                        Task {
                            testResult = await model.testProvider(draft)
                            isTesting = false
                        }
                    } label: {
                        HStack {
                            Text(L("测试 API 连接"))
                            Spacer()
                            if isTesting {
                                ProgressView().controlSize(.mini)
                            } else if let ok = model.providerStatus[draft.id] {
                                Circle().fill(ok ? Color.green : Color.red).frame(width: 8, height: 8)
                            }
                        }
                    }
                    .disabled(isTesting)

                    if let testResult {
                        Text(testResult)
                            .font(.caption)
                            .foregroundStyle(testResult.hasPrefix(L("连接成功"))
                                             ? AnyShapeStyle(.green) : AnyShapeStyle(.red))
                            .textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(L("新增供应商"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            #if os(macOS)
            .frame(width: sheetSize.width, height: sheetSize.height)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("取消")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("完成")) {
                        var final = draft
                        // Empty address is fine when the name matches a preset.
                        if final.baseURL.trimmingCharacters(in: .whitespaces).isEmpty,
                           let preset = ProviderPreset.all.first(where: { $0.name == final.name }) {
                            final.baseURL = preset.baseURL
                        }
                        onSave(final)
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
