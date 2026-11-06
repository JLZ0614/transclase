import Speech
import SwiftUI
import Translation

/// Lists what is actually on disk. Apple exposes no API to delete either kind of
/// model — speech assets are reserved/released rather than removed, and the
/// translation framework has no removal call at all — so this screen is honest
/// about that instead of shipping a button that silently does nothing.
struct ModelManagerView: View {
    @EnvironmentObject private var model: AppModel

    @State private var speechInstalled: [String] = []
    @State private var translationInstalled: [String] = []
    @State private var isLoading = true

    var body: some View {
        List {
            Section {
                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(L("正在检查…")).foregroundStyle(.secondary)
                    }
                } else if speechInstalled.isEmpty {
                    Text(L("没有已安装的识别模型")).foregroundStyle(.secondary)
                } else {
                    ForEach(speechInstalled, id: \.self) { id in
                        row(
                            title: LanguageMapping.displayName(forBCP47: id),
                            badge: id == model.settings.sourceLanguageID ? L("当前") : nil
                        )
                    }
                }
            } header: {
                Text("识别模型 · \(isLoading ? "…" : "\(speechInstalled.count)")")
            } footer: {
                Text(L("这些模型由系统统一管理，App 无法单独删除。磁盘紧张时系统会自动清理长期未用的模型。"))
            }

            Section {
                if !isLoading {
                    if translationInstalled.isEmpty {
                        Text(L("没有已安装的翻译语言包")).foregroundStyle(.secondary)
                    } else {
                        ForEach(translationInstalled, id: \.self) { id in
                            row(
                                title: LanguageMapping.displayName(forBCP47: id),
                                badge: id == model.settings.targetLanguageID ? L("当前") : nil
                            )
                        }
                    }
                }

                Button {
                    Task { await model.prepareOfflinePack() }
                } label: {
                    Label(L("下载当前语言对"), systemImage: "arrow.down.circle")
                }
                .disabled(model.isPreparingPack || model.isRunning)
            } header: {
                Text("翻译语言包 · \(isLoading ? "…" : "\(translationInstalled.count)")")
            } footer: {
                Text("删除语言包需要在系统里操作：\n• iPhone / iPad：设置 → 翻译 → 已下载的语言\n• Mac：系统设置 → 通用 → 语言与地区 → 翻译语言")
            }
        }
        .navigationTitle(L("模型"))
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func row(title: String, badge: String?) -> some View {
        HStack(spacing: 8) {
            Text(title)
            if let badge {
                Text(badge)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
            }
            Spacer(minLength: 4)
            Text(L("已安装"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func refresh() async {
        isLoading = true

        let speech = await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) }
        speechInstalled = speech.sorted {
            LanguageMapping.displayName(forBCP47: $0) < LanguageMapping.displayName(forBCP47: $1)
        }

        // Translation status is only exposed per language *pair*, and each query
        // round-trips to a system daemon — sequential scanning can take minutes.
        // Probe concurrently with a hard timeout so this screen always renders.
        let languages = await LanguageAvailability().supportedLanguages
        let probeTargets = languages.filter { $0.minimalIdentifier != "en" }
        let found = await withTaskGroup(of: String?.self) { group -> [String] in
            for language in probeTargets {
                group.addTask {
                    let isInstalled = await withTimeout(seconds: 1.5) {
                        await LanguageAvailability()
                            .status(from: Locale.Language(identifier: "en"), to: language) == .installed
                    } ?? false
                    return isInstalled ? LanguageMapping.settingsID(for: language) : nil
                }
            }
            var result: [String] = []
            for await item in group {
                if let item { result.append(item) }
            }
            return result
        }

        var installed = found.sorted {
            LanguageMapping.displayName(forBCP47: $0) < LanguageMapping.displayName(forBCP47: $1)
        }
        // Fall back to the pair the app already knows about, in case the daemon
        // timed out on everything.
        if !installed.contains(model.settings.targetLanguageID),
           model.isTranslationPackInstalled {
            installed.append(model.settings.targetLanguageID)
        }
        if !installed.isEmpty {
            installed.insert("en", at: 0)
        }
        translationInstalled = installed

        isLoading = false
    }
}
