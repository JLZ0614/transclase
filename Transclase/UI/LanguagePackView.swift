import SwiftUI
import Translation

/// Lists what the Translation framework can do on this device: packs already on
/// disk and packs that can be downloaded — the same split the system Translate
/// app shows.
struct LanguagePackView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var installed: [(id: String, name: String)] = []
    @State private var downloadable: [(id: String, name: String)] = []
    @State private var isLoading = true

    var body: some View {
        List {
            if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                    Text(L("正在查询本机语言包…"))
                        .foregroundStyle(.secondary)
                }
            } else {
                Section(L("已下载")) {
                    if installed.isEmpty {
                        Text(L("还没有下载任何语言包"))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(installed, id: \.id) { item in
                        row(item)
                    }
                }

                Section(L("可下载")) {
                    if downloadable.isEmpty {
                        Text(L("没有更多可下载的语言"))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(downloadable, id: \.id) { item in
                        row(item)
                    }
                }
            }
        }
        .navigationTitle(L("离线语言包"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await load() }
    }

    private func row(_ item: (id: String, name: String)) -> some View {
        HStack {
            Text(item.name)
            Spacer()
            if item.id == model.settings.targetLanguageID {
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            model.settings.targetLanguageID = item.id
            model.syncTranslationConfiguration()
            Task { await model.refreshLanguagePackStatus() }
        }
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        let availability = LanguageAvailability()
        let supported = await availability.supportedLanguages
        let source = LanguageMapping.translationLanguage(model.settings.sourceLanguageID)

        var installedList: [(String, String)] = []
        var downloadableList: [(String, String)] = []

        for language in supported {
            let id = language.maximalIdentifier
            guard id != source.maximalIdentifier else { continue }
            let name = LanguageMapping.displayName(forLanguage: language)
            let status = await availability.status(from: source, to: language)
            switch status {
            case .installed:
                installedList.append((id, name))
            case .supported:
                downloadableList.append((id, name))
            default:
                continue
            }
        }

        installed = installedList.sorted { $0.1 < $1.1 }
        downloadable = downloadableList.sorted { $0.1 < $1.1 }
    }
}
