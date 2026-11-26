import SwiftUI

/// 「设置」是唯一的配置入口：翻译引擎、模型服务商、显示、行为、助手、关于。
struct SettingsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var isTesting = false
    @State private var testResult: String?
    @State private var keyDraft = ""
    @State private var needsRelaunch = false

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    /// A sheet must never exceed its parent window — clamp to the window minus a
    /// margin, whatever the window's current size is.
    private var sheetSize: CGSize {
        let window = model.windowSize
        let width = min(max(460, window.width * 0.72), min(640, window.width - 60))
        let height = min(max(360, window.height * 0.78), min(560, window.height - 90))
        return CGSize(width: width, height: height)
    }

    var body: some View {
        NavigationStack {
            Form {
                languageSection
                translationSection
                providerSection
                displaySection
                assistantSection
                aboutSection
                privacySection
            }
            .formStyle(.grouped)
            .navigationTitle(L("设置"))
            // Packs downloaded in the system Translate app show up here without
            // restarting the session.
            .task { await model.refreshLanguagePackStatus() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("完成")) { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(width: sheetSize.width, height: sheetSize.height)
        #endif
        .onAppear {
            if model.settings.activeProviderID == nil {
                model.settings.activeProviderID = model.settings.providers.first?.id
            }
            keyDraft = model.activeProvider.flatMap { model.providerKey($0) } ?? ""
        }
        .onChange(of: model.settings.activeProviderID) { _, _ in
            keyDraft = model.activeProvider.flatMap { model.providerKey($0) } ?? ""
        }
        .onChange(of: keyDraft) { _, value in
            if let provider = model.activeProvider { model.saveProviderKey(provider, key: value) }
        }
    }

    // MARK: - 语言

    private var languageSection: some View {
        Section {
            Picker(L("语言"), selection: $model.settings.appLanguage) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.title).tag(language)
                }
            }
            .onChange(of: model.settings.appLanguage) { _, language in
                model.switchLanguage(language)
            }
        } header: {
            Text(L("语言"))
        }
    }

    // MARK: - 翻译

    private var translationSection: some View {
        Section {
            Picker(L("翻译引擎"), selection: $model.settings.translationEngine) {
                ForEach(TranslationEngineKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            .disabled(model.isRunning)

            if model.settings.translationEngine == .apple {
                Toggle(L("高质量翻译"), isOn: $model.settings.highFidelityTranslation)
                    .disabled(model.isRunning)            }


            if model.settings.translationEngine != .apple {
                Button {
                    Task { await model.testTranslationEngine() }
                } label: {
                    Label(model.isTestingEngine ? L("测试中…") : L("测试连接"), systemImage: "bolt.horizontal")
                }
                .disabled(model.isRunning || model.isTestingEngine)

                if let result = model.engineTestResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Button {
                dismiss()
                Task {
                    try? await Task.sleep(for: .milliseconds(300))
                    await model.downloadLanguagePack()
                }
            } label: {
                Label(L("下载 / 刷新离线语言包"), systemImage: "arrow.down.circle")
            }
            .disabled(model.isRunning)

            NavigationLink {
                ModelManagerView().environmentObject(model)
            } label: {
                Label(L("已下载的模型"), systemImage: "internaldrive")
            }
        } header: {
            Text(L("翻译"))
        }
    }

    // MARK: - 模型服务商

    private var providerSection: some View {
        Section {
            Picker(L("服务商"), selection: $model.settings.activeProviderID) {
                ForEach(model.settings.providers) { provider in
                    Text(provider.name).tag(Optional(provider.id))
                }
            }
            .disabled(model.isRunning)

            if model.activeProvider != nil {
                TextField(L("名称"), text: providerBinding(\.name, fallback: ""))
                    .textFieldStyle(.roundedBorder)
                TextField(L("地址"), text: providerBinding(\.baseURL, fallback: ""))
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Picker(L("模型"), selection: providerBinding(\.model, fallback: "")) {
                        ForEach(modelOptions, id: \.self) { Text($0).tag($0) }
                    }
                    Button {
                        if let provider = model.activeProvider {
                            Task { await model.loadModels(for: provider) }
                        }
                    } label: {
                        if model.isLoadingModels {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                    }
                    .buttonStyle(.borderless)
                    .help(L("从服务商拉取模型列表"))
                }

                if let error = model.modelListError {
                    Text(error)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }

                SecureField("API Key", text: $keyDraft)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()

                if let provider = model.activeProvider {
                    Text(String(format: NSLocalizedString("已保存：%@", comment: ""),
                                model.providerKeyFingerprint(provider)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Button {
                    testResult = nil
                    isTesting = true
                    Task {
                        testResult = await model.testProviderConnection()
                        isTesting = false
                    }
                } label: {
                    HStack {
                        Text(L("测试 API 连接"))
                        Spacer()
                        if isTesting {
                            ProgressView().controlSize(.mini)
                        }
                    }
                }
                .disabled(isTesting)

                if let testResult {
                    Text(testResult)
                        .font(.caption)
                        .foregroundStyle(testResult.hasPrefix(L("连接成功")) ? AnyShapeStyle(.green) : AnyShapeStyle(.red))
                }

                HStack {
                    Button {
                        addProvider()
                    } label: {
                        Label(L("添加服务商"), systemImage: "plus")
                    }
                    Spacer()
                    Button(role: .destructive) {
                        removeActiveProvider()
                    } label: {
                        Label(L("删除"), systemImage: "minus")
                    }
                    .disabled(model.settings.providers.count <= 1)
                }
                .buttonStyle(.borderless)
            }
        } header: {
            Text(L("模型服务商"))
        } footer: {
            Text(L("地址需要以 /v1 结尾。翻译引擎选「云端 API」和翻译助手都用这一份配置。"))
        }
    }

    private var modelOptions: [String] {
        guard let provider = model.activeProvider else { return [] }
        var ids = model.providerModels
        if !ids.contains(provider.model) { ids.insert(provider.model, at: 0) }
        return ids
    }

    private func providerBinding(
        _ keyPath: WritableKeyPath<ModelProvider, String>,
        fallback: String
    ) -> Binding<String> {
        Binding(
            get: { model.activeProvider?[keyPath: keyPath] ?? fallback },
            set: { newValue in
                guard let provider = model.activeProvider else { return }
                model.updateProvider(provider.id) { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func addProvider() {
        var provider = ModelProvider.preset()
        provider.name = L("新服务商")
        provider.baseURL = "https://api.openai.com/v1"
        provider.model = "gpt-4o-mini"
        model.settings.providers.append(provider)
        model.settings.activeProviderID = provider.id
    }

    private func removeActiveProvider() {
        guard let provider = model.activeProvider, model.settings.providers.count > 1 else { return }
        CredentialStore.delete("provider.\(provider.id.uuidString)")
        model.settings.providers.removeAll { $0.id == provider.id }
        model.settings.activeProviderID = model.settings.providers.first?.id
    }

    // MARK: - 其它

    private var displaySection: some View {
        Section(L("显示")) {
            Picker(L("外观"), selection: $model.settings.appearance) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.title).tag(appearance)
                }
            }
            .pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(L("译文字号"))
                    Spacer()
                    Text("\(Int(model.settings.fontSize)) pt")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $model.settings.fontSize, in: 16...44, step: 1)
            }
            Toggle(L("显示原文"), isOn: $model.settings.showOriginal)
            Toggle(L("自动跟随最新字幕"), isOn: $model.settings.autoScroll)
        }
    }

    private var assistantSection: some View {
        Section(L("翻译助手")) {
            Toggle(L("自动总结要点"), isOn: $model.settings.assistantEnabled)
            LabeledContent(L("总结间隔")) {
                Picker("", selection: $model.settings.summaryIntervalMinutes) {
                    ForEach(Array(1...10), id: \.self) { m in
                        Text(String(format: NSLocalizedString("每 %d 分钟", comment: ""), m)).tag(m)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
            }
        }
    }

    private var aboutSection: some View {
        Section(L("关于")) {
            LabeledContent(L("版本"), value: version)
            LabeledContent(L("本机能力")) {
                Text("识别 \(model.speechOptions.count) · 翻译 \(model.translationOptions.count)")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var privacySection: some View {
        Section(L("隐私")) {
            Text(L("音频只在本机内存中处理。开启云端翻译或助手后，识别出的文字会发送到所配置的服务商。录音前请确认所在学校与当地法律对课堂录音的要求。"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
