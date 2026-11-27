import SwiftUI

/// 「设置」是唯一的配置入口：翻译引擎、模型服务商、显示、行为、助手、关于。
/// One sheet state for both "edit existing" and "create new" — two separate
/// `.sheet` modifiers on the same view can silently swallow one another.
enum ProviderSheet: Identifiable {
    case editor(ModelProvider)
    case draft(ModelProvider)

    var id: String {
        switch self {
        case .editor(let provider): "editor-\(provider.id)"
        case .draft(let seed): "draft-\(seed.id)"
        }
    }
}

struct SettingsSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var isTesting = false
    @State private var providerSheet: ProviderSheet?
    @State private var isTestingPlaceholder = false
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
        SheetMetrics.size(for: model.windowSize)
    }

    var body: some View {
        NavigationStack {
            Form {
                languageSection
                translationSection
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
            .task { await model.testAllProviders() }
            .sheet(item: $providerSheet) { sheet in
                switch sheet {
                case .editor(let provider):
                    ProviderEditorView(providerID: provider.id)
                        .environmentObject(model)
                case .draft(let seed):
                    ProviderDraftEditor(seed: seed) { provider in
                        model.settings.providers.append(provider)
                        model.settings.activeProviderID = provider.id
                        model.settings.translationEngine = .cloud
                        providerSheet = nil
                    }
                    .environmentObject(model)
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
            engineRow(
                title: L("系统离线翻译"),
                selected: model.settings.translationEngine == .apple
            ) {
                model.settings.translationEngine = .apple
                model.syncTranslationConfiguration(force: true)
            }

            if model.settings.translationEngine == .apple {
                Text(L("语言包在「系统设置 → 通用 → 语言与地区 → 翻译语言」中下载。"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ForEach(model.settings.providers) { provider in
                HStack(spacing: 8) {
                    engineRow(
                        title: provider.name,
                        selected: model.settings.translationEngine == .cloud
                            && model.settings.activeProviderID == provider.id
                    ) {
                        model.settings.activeProviderID = provider.id
                        model.settings.translationEngine = .cloud
                    }

                    Circle()
                        .fill(dotColor(for: provider))
                        .frame(width: 7, height: 7)

                    Spacer(minLength: 8)

                    Button(L("编辑")) { providerSheet = .editor(provider) }
                        .buttonStyle(.borderless)
                        .disabled(model.isRunning)
                }
            }

            Button {
                providerSheet = .draft(ModelProvider(name: "", baseURL: "",
                                                    model: "", models: []))
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text(L("添加模型供应商"))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
        } header: {
            Text(L("翻译模型"))
        }
    }

    private func dotColor(for provider: ModelProvider) -> Color {
        switch model.providerStatus[provider.id] {
        case .some(true): return .green
        case .some(false): return .red
        case .none: return Color.secondary.opacity(0.35)
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
