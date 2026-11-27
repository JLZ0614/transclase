import SwiftUI

/// Editor for one provider. Flat form: name, address, model list, key, test.
/// No nested menus — every action is a visible row.
struct ProviderEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let providerID: UUID

    @State private var keyDraft = ""
    @State private var isTesting = false
    @State private var testResult: String?
    @State private var showNewModel = false
    @State private var newModelName = ""

    private var provider: ModelProvider? {
        model.settings.providers.first { $0.id == providerID }
    }

    private func binding(_ keyPath: WritableKeyPath<ModelProvider, String>) -> Binding<String> {
        Binding(
            get: { provider?[keyPath: keyPath] ?? "" },
            set: { newValue in
                guard let index = model.settings.providers.firstIndex(where: { $0.id == providerID })
                else { return }
                model.settings.providers[index][keyPath: keyPath] = newValue
            }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                if let provider {
                    Section {
                        TextField(L("名称"), text: binding(\.name))
                        TextField(L("地址"), text: binding(\.baseURL))
                            .autocorrectionDisabled()
                    }

                    Section(L("模型")) {
                        modelList(provider)
                    }

                    Section {
                        SecureField("API Key", text: $keyDraft)
                            .autocorrectionDisabled()
                            .onChange(of: keyDraft) { _, value in
                                model.saveProviderKey(provider, key: value)
                            }

                        if !provider.apiKeyURL.isEmpty, let url = URL(string: provider.apiKeyURL) {
                            Link(destination: url) {
                                Label(L("获取 API Key"), systemImage: "arrow.up.right.square")
                            }
                        }

                        testButton(provider)

                        if let testResult {
                            Text(testResult)
                                .font(.caption)
                                .foregroundStyle(testResult.hasPrefix(L("连接成功"))
                                                 ? AnyShapeStyle(.green) : AnyShapeStyle(.red))
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(provider?.name ?? L("服务商"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("完成")) { dismiss() }
                }
            }
            .onAppear {
                if let provider { keyDraft = model.providerKey(provider) ?? "" }
            }
            .alert(L("添加模型"), isPresented: $showNewModel) {
                TextField(L("模型名称"), text: $newModelName)
                Button(L("取消"), role: .cancel) { newModelName = "" }
                Button(L("添加")) {
                    model.addModel(newModelName, to: providerID)
                    newModelName = ""
                }
            }
        }
    }

    @ViewBuilder
    private func modelList(_ provider: ModelProvider) -> some View {
        ForEach(provider.models, id: \.self) { name in
            HStack {
                Button {
                    setModel(name)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: name == provider.model
                              ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(name == provider.model
                                             ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        Text(name)
                            .foregroundStyle(.primary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                if provider.models.count > 1 {
                    Button {
                        model.removeModel(name, from: providerID)
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }

        Button {
            newModelName = ""
            showNewModel = true
        } label: {
            Label(L("添加模型"), systemImage: "plus.circle")
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private func testButton(_ provider: ModelProvider) -> some View {
        Button {
            testResult = nil
            isTesting = true
            Task {
                testResult = await model.testProvider(provider)
                isTesting = false
            }
        } label: {
            HStack {
                Text(L("测试 API 连接"))
                Spacer()
                if isTesting {
                    ProgressView().controlSize(.mini)
                } else if let ok = model.providerStatus[providerID] {
                    Circle()
                        .fill(ok ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                }
            }
        }
        .disabled(isTesting)
    }

    private func setModel(_ name: String) {
        guard let index = model.settings.providers.firstIndex(where: { $0.id == providerID })
        else { return }
        model.settings.providers[index].model = name
    }
}
