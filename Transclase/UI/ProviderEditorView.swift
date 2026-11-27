import SwiftUI

/// Editor for one provider: rename, address, models, API key, delete.
/// Flat form — no nested menus.
struct ProviderEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let providerID: UUID

    @State private var keyDraft = ""
    @State private var isTesting = false
    @State private var testResult: String?
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

                    Section {
                        Button(role: .destructive) {
                            deleteProvider()
                        } label: {
                            Text(L("删除该供应商"))
                        }
                        .disabled(model.settings.providers.count <= 1)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(provider?.name ?? L("模型供应商"))
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

        HStack(spacing: 8) {
            TextField(L("新模型名称"), text: $newModelName)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
            Button(L("添加")) {
                model.addModel(newModelName, to: providerID)
                newModelName = ""
            }
            .buttonStyle(.borderless)
            .disabled(newModelName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
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
                    Circle().fill(ok ? Color.green : Color.red).frame(width: 8, height: 8)
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

    private func deleteProvider() {
        guard let provider, model.settings.providers.count > 1 else { return }
        CredentialStore.delete("provider.\(provider.id.uuidString)")
        model.settings.providers.removeAll { $0.id == provider.id }
        model.settings.activeProviderID = model.settings.providers.first?.id
        model.settings.translationEngine = .apple
        dismiss()
    }
}
