import SwiftUI

/// 「设置」是唯一的配置入口：翻译引擎、模型服务商、显示、行为、助手、关于。
struct SettingsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var isTesting = false
    @State private var engineTestName = ""
    @State private var engineTestResult: String?
    @State private var showNewModel = false
    @State private var newModelName = ""
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
                packsSection
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
        .alert(L("添加模型"), isPresented: $showNewModel) {
            TextField(L("模型名称"), text: $newModelName)
            Button(L("取消"), role: .cancel) { newModelName = "" }
            Button(L("添加")) {
                if let provider = model.activeProvider {
                    model.addModel(newModelName, to: provider.id)
                }
                newModelName = ""
            }
        }
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

    @ViewBuilder
    private var packsSection: some View {
        Section {
            NavigationLink {
                ModelManagerView().environmentObject(model)
            } label: {
                LabeledContent(L("已下载的识别模型")) {
                    Text(model.isSpeechModelInstalled ? L("已安装") : L("未安装"))
                        .foregroundStyle(.secondary)
                }
            }

            NavigationLink {
                LanguagePackView().environmentObject(model)
            } label: {
                LabeledContent(L("离线翻译语言包")) {
                    Text(model.isTranslationPackInstalled ? L("已安装") : L("未下载"))
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(L("离线可用"))
        }
    }

    private var translationSection: some View {
        Section {
            engineRow(
                title: L("系统离线翻译"),
                selected: model.settings.translationEngine == .apple
            ) {
                model.settings.translationEngine = .apple
                model.syncTranslationConfiguration(force: true)
            }

            ForEach(model.settings.providers) { provider in
                HStack {
                    engineRow(
                        title: provider.name,
                        selected: model.settings.translationEngine == .cloud
                            && model.settings.activeProviderID == provider.id
                    ) {
                        model.settings.activeProviderID = provider.id
                        model.settings.translationEngine = .cloud
                    }

                    Spacer(minLength: 8)

                    Button(L("测试")) {
                        engineTestName = provider.name
                        engineTestResult = nil
                        Task { engineTestResult = await model.testProvider(provider) }
                    }
                    .buttonStyle(.borderless)
                    .disabled(model.isRunning)
                }
            }

            if let engineTestResult {
                Text("\(engineTestName)：\(engineTestResult)")
                    .font(.caption)
                    .foregroundStyle(engineTestResult.hasPrefix(L("连接成功"))
                                     ? AnyShapeStyle(.green) : AnyShapeStyle(.red))
                    .textSelection(.enabled)
            }
        } header: {
            Text(L("翻译"))
        }
    }

    private func engineRow(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                Text(title)
                    .foregroundStyle(.primary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isRunning)
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

            if let provider = model.activeProvider {
                SecureField("API Key", text: $keyDraft)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()

                if let urlString = provider.apiKeyURL.isEmpty ? nil : provider.apiKeyURL,
                   let url = URL(string: urlString) {
                    Link(destination: url) {
                        Label(L("获取 API Key"), systemImage: "arrow.up.right.square")
                    }
                }

                modelRows(for: provider)

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
                        if isTesting { ProgressView().controlSize(.mini) }
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

                if provider.apiKeyURL.isEmpty {
                    TextField(L("名称"), text: providerBinding(\.name, fallback: ""))
                        .textFieldStyle(.roundedBorder)
                    TextField(L("地址"), text: providerBinding(\.baseURL, fallback: ""))
                        .textFieldStyle(.roundedBorder)
                }
            }

            Menu {
                ForEach(ProviderPreset.all) { preset in
                    Button(preset.name) { addProvider(preset) }
                }
                Divider()
                Button(L("自定义服务商")) { addProvider(nil) }
            } label: {
                Label(L("添加模型服务商"), systemImage: "plus")
            }

            Button(role: .destructive) {
                removeActiveProvider()
            } label: {
                Label(L("删除当前服务商"), systemImage: "minus")
            }
            .disabled(model.settings.providers.count <= 1)
        } header: {
            Text(L("模型服务商"))
        }
    }

    /// Model list for one provider: pick one, add new ones, delete the extras.
    @ViewBuilder
    private func modelRows(for provider: ModelProvider) -> some View {
        Picker(L("模型"), selection: providerBinding(\.model, fallback: "")) {
            ForEach(provider.models, id: \.self) { Text($0).tag($0) }
        }
        .disabled(model.isRunning)

        ForEach(provider.models, id: \.self) { name in
            if name != provider.models.first || provider.models.count > 1 {
                HStack {
                    Text(name)
                        .foregroundStyle(name == provider.model ? .primary : .secondary)
                    Spacer()
                    Button {
                        model.removeModel(name, from: provider.id)
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .disabled(provider.models.count <= 1)
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

    private func addProvider(_ preset: ProviderPreset?) {
        let provider: ModelProvider
        if let preset {
            provider = ModelProvider.make(from: preset)
        } else {
            provider = ModelProvider(
                name: L("自定义服务商"),
                baseURL: "",
                model: "",
                models: [],
                apiKeyURL: ""
            )
        }
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
            if model.settings.translationEngine == .apple {
                LabeledContent(L("实际策略"), value: model.effectiveTranslationStrategy)
            }
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
