import Combine
import Foundation
import Speech
import Translation

@MainActor
final class AppModel: ObservableObject {
    @Published var settings: AppSettings
    @Published var captions: [Caption] = []
    @Published var isRunning = false
    @Published var isPreparing = false
    @Published var statusText = "就绪"
    @Published var errorMessage: String?
    @Published var level: Float = 0
    @Published var scrollGeneration = 0
    @Published var isPinnedToBottom = true
    @Published var startedAt: Date?
    @Published var translationConfiguration: TranslationSession.Configuration?
    @Published var translationNote: String?
    @Published var translationEngineLabel = "—"
    @Published var languagePackStatus = "未知"
    @Published var pendingClearConfirmation = false
    @Published var speechProgress: Double?
    @Published var isPreparingPack = false
    @Published var exportDocument: MarkdownDocument?
    @Published var isExporting = false
    @Published var isBootstrapping = true
    @Published var speechOptions: [LanguageOption] = []
    @Published var translationOptions: [LanguageOption] = []

    private let pipeline = CaptionPipeline()
    private var markdownCache: (stamp: Int, text: String) = (-1, "")
    private var transientDemo = false
    private var translationSession: TranslationSession?

    init() {
        settings = AppSettings.load()
        pipeline.onCaptionsChanged = { [weak self] captions in
            guard let self else { return }
            self.captions = captions
            self.scrollGeneration &+= 1
        }
        pipeline.onStatus = { [weak self] message in
            self?.statusText = message
        }
        pipeline.onError = { [weak self] message in
            self?.errorMessage = message
        }
        pipeline.onLevel = { [weak self] level in
            self?.level = level
        }
        pipeline.onTranslationEngine = { [weak self] label in
            self?.translationEngineLabel = label
        }
        pipeline.onSpeechDownloadProgress = { [weak self] fraction in
            self?.speechProgress = fraction >= 1 ? nil : fraction
        }
    }

    // MARK: - Capabilities

    /// Demo mode, either chosen in settings or forced for this launch with
    /// `--demo`. Never written back to settings so a test run can't leave the
    /// app permanently in demo mode.
    var isDemoActive: Bool { settings.demoMode || Self.wantsDemo || transientDemo }

    /// "看演示" must not flip a persisted setting — otherwise the app stays in
    /// fake-lecture mode forever and the next real session is nonsense.
    func playDemo() async {
        transientDemo = true
        await start()
    }

    var isFoundationModelAvailable: Bool { FoundationModelTranslationEngine.isAvailable }

    /// Recognition model for the chosen source locale is on disk.
    var isSpeechModelInstalled: Bool {
        speechOptions.first { $0.id == settings.sourceLanguageID }?.isInstalled ?? false
    }

    var isTranslationPackInstalled: Bool { languagePackStatus == "已安装" }

    /// Everything needed to work with no network and no further downloads.
    var isReadyOffline: Bool {
        guard !isDemoActive else { return true }
        return isSpeechModelInstalled && isTranslationPackInstalled
    }

    var speechLanguages: Set<String> { Set(speechOptions.map(\.id)) }
    var translationLanguages: Set<String> { Set(translationOptions.map(\.id)) }

    func bootstrap() async {
        guard speechOptions.isEmpty else {
            isBootstrapping = false
            return
        }
        let catalog = await LanguageCatalog.load()
        speechOptions = catalog.speech
        translationOptions = catalog.translation
        validateLanguages()
        syncTranslationConfiguration()
        isBootstrapping = false
    }

    private func validateLanguages() {
        if !speechOptions.isEmpty,
           !speechLanguages.contains(settings.sourceLanguageID) {
            settings.sourceLanguageID = speechOptions.first(where: { $0.id == "en-US" })?.id
                ?? speechOptions[0].id
        }
        if !translationOptions.isEmpty,
           !translationLanguages.contains(settings.targetLanguageID) {
            settings.targetLanguageID = translationOptions.first(where: { $0.id == "zh-Hans" })?.id
                ?? translationOptions[0].id
        }
        if settings.sourceLanguageID == settings.targetLanguageID,
           let alternative = translationOptions.first(where: { $0.id != settings.sourceLanguageID }) {
            settings.targetLanguageID = alternative.id
        }
    }

    func syncTranslationConfiguration(force: Bool = false) {
        guard !isDemoActive else {
            translationConfiguration = nil
            return
        }
        let source = LanguageMapping.translationLanguage(settings.sourceLanguageID)
        let target = LanguageMapping.translationLanguage(settings.targetLanguageID)

        if var existing = translationConfiguration,
           existing.source == source,
           existing.target == target {
            guard force else { return }
            // `Configuration.version` only climbs when you invalidate the *same*
            // value. A freshly built configuration always starts at 0, so
            // "new + invalidate" is always version 1 and compares equal to the
            // last one — SwiftUI then never re-runs `.translationTask` and the
            // download prompt never appears a second time.
            existing.invalidate()
            translationConfiguration = existing
            return
        }

        translationConfiguration = TranslationSession.Configuration(source: source, target: target)
        Task { await refreshLanguagePackStatus() }
    }

    func refreshLanguagePackStatus() async {
        guard !isDemoActive else {
            languagePackStatus = "演示模式无需语言包"
            return
        }
        let status = await LanguageAvailability().status(
            from: LanguageMapping.translationLanguage(settings.sourceLanguageID),
            to: LanguageMapping.translationLanguage(settings.targetLanguageID)
        )
        switch status {
        case .installed:
            languagePackStatus = "已安装"
        case .supported:
            languagePackStatus = "未下载"
        default:
            languagePackStatus = "不支持该语言对"
        }
    }

    /// Bumps the configuration so `.translationTask` re-runs and the system
    /// download prompt appears for the current pair.
    func downloadLanguagePack() async {
        guard !isRunning else { return }
        syncTranslationConfiguration(force: true)
        try? await Task.sleep(for: .seconds(3))
        await refreshLanguagePackStatus()
        if languagePackStatus != "已安装" {
            translationNote = "没看到下载面板的话，去 系统设置 → 通用 → 语言与地区 → 翻译语言，手动添加该语言。"
        } else {
            translationNote = "语言包已安装，重启一次识别后生效。"
        }
    }

    /// Called by the `.translationTask` modifier. Apple only hands out sessions
    /// here that are allowed to trigger a language-pack download, so the
    /// translation engine asks the model for a session instead of creating one.
    func adoptTranslationSession(_ session: TranslationSession) {
        translationSession = session
        Task { [weak self] in
            guard let self else { return }
            do {
                try await session.prepareTranslation()
            } catch {
                self.translationNote = "语言包未就绪：\(error.localizedDescription)"
                return
            }
            // `prepareTranslation()` only *offers* the download; it does not
            // guarantee the pack landed, so ask the framework afterwards.
            let status = await LanguageAvailability().status(
                from: LanguageMapping.translationLanguage(self.settings.sourceLanguageID),
                to: LanguageMapping.translationLanguage(self.settings.targetLanguageID)
            )
            switch status {
            case .installed:
                self.translationNote = "语言包已就绪（全程离线）"
            case .supported:
                self.translationNote = "语言包尚未下载：点上面的按钮，在系统面板里确认下载"
            default:
                self.translationNote = "这台设备不支持这个语言对"
            }
        }
    }

    static var wantsDemo: Bool {
        ProcessInfo.processInfo.arguments.contains("--demo")
            || ProcessInfo.processInfo.environment["LECSUB_SELFTEST"] == "1"
    }

    static var wantsSelfTest: Bool {
        ProcessInfo.processInfo.arguments.contains("--selftest")
            || ProcessInfo.processInfo.environment["LECSUB_SELFTEST"] == "1"
    }

    // MARK: - Offline preparation

    /// Explicitly fetch everything a lecture needs: the recognition model and
    /// the translation language pack. Safe to call repeatedly.
    func prepareOfflinePack() async {
        guard !isPreparingPack else { return }
        isPreparingPack = true
        errorMessage = nil
        defer {
            isPreparingPack = false
            speechProgress = nil
        }

        do {
            let locale = LanguageMapping.speechLocale(settings.sourceLanguageID)
            guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
                throw ASRError.unsupportedLocale(locale.identifier)
            }
            try await SpeechModelInstaller.ensureInstalled(
                module: AppleSpeechEngine.makeTranscriber(locale: supported),
                locale: supported
            ) { [weak self] fraction in
                Task { @MainActor in
                    self?.speechProgress = fraction >= 1 ? nil : fraction
                }
            }
            await refreshCapabilities()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        // The translation pack can only be requested through the system prompt
        // owned by `.translationTask`.
        syncTranslationConfiguration(force: true)
        try? await Task.sleep(for: .seconds(1.2))
        await refreshLanguagePackStatus()
    }

    func refreshCapabilities() async {
        let catalog = await LanguageCatalog.load()
        speechOptions = catalog.speech
        translationOptions = catalog.translation
    }

    // MARK: - Run control

    func toggle() async {
        if isRunning {
            await stop()
        } else {
            await start()
        }
    }

    func start() async {
        guard !isRunning, !isPreparing else { return }
        isPreparing = true
        errorMessage = nil
        defer { isPreparing = false }

        var effective = settings
        effective.demoMode = isDemoActive

        do {
            try await pipeline.start(
                settings: effective,
                sessionProvider: { [weak self] in self?.translationSession }
            )
            isRunning = true
            startedAt = Date()
        } catch {
            await pipeline.stop()
            errorMessage = error.localizedDescription
            statusText = "启动失败"
            isRunning = false
        }
    }

    func stop() async {
        guard isRunning else { return }
        await pipeline.stop()
        isRunning = false
        level = 0
        transientDemo = false
    }

    func requestClear() {
        guard !captions.isEmpty else { return }
        pendingClearConfirmation = true
    }

    var exportFilename: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return "transcript-\(formatter.string(from: startedAt ?? Date()))"
    }

    /// Source-language transcript, saved wherever the user picks.
    func exportSourceMarkdown() {
        let finals = captions.filter(\.isFinal)
        guard !finals.isEmpty else { return }
        exportDocument = MarkdownDocument(
            text: SessionExport.sourceMarkdown(
                captions: finals,
                languageName: sourceName,
                startedAt: startedAt ?? Date()
            )
        )
        isExporting = true
    }

    func clear() {
        pipeline.clear()
        startedAt = nil
        pendingClearConfirmation = false
        markdownCache = (-1, "")
    }

    func saveSettings() {
        settings.save()
    }

    // MARK: - Derived values

    var sourceName: String {
        speechOptions.first(where: { $0.id == settings.sourceLanguageID })?.displayName
            ?? LanguageMapping.displayName(forBCP47: settings.sourceLanguageID)
    }

    var targetName: String {
        translationOptions.first(where: { $0.id == settings.targetLanguageID })?.displayName
            ?? settings.targetLanguageID
    }

    var pairLabel: String {
        "\(sourceName) → \(targetName)"
    }

    /// Cached by the number of finalized segments: partial updates fire ~10x a
    /// second and must not rebuild the whole document.
    var translationMarkdown: String {
        let finals = captions.filter(\.isFinal)
        // Signature must change when a translation lands, otherwise the export
        // silently keeps the pre-translation text.
        let translated = finals.reduce(0) { $0 + (($1.target?.isEmpty == false) ? 1 : 0) }
        let stamp = finals.count * 10_000 + translated
        if markdownCache.stamp == stamp, !markdownCache.text.isEmpty {
            return markdownCache.text
        }
        let text = SessionExport.markdown(
            captions: finals,
            sourceName: sourceName,
            targetName: targetName,
            startedAt: startedAt ?? Date()
        )
        markdownCache = (stamp, text)
        return text
    }

    var plainText: String {
        SessionExport.plainText(captions: captions)
    }

    var totalWords: Int {
        captions.reduce(0) { $0 + $1.wordCount }
    }

    // MARK: - Headless smoke test

    /// `LECSUB_SELFTEST=1` runs the whole pipeline in demo mode and prints the
    /// transcript to stderr. Useful in CI or when checking a build without a
    /// microphone or without the translation language packs installed.
    func runSelfTest() async {
        settings.demoMode = true
        log("selftest: starting")
        await start()

        for step in 0..<6 {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            log("selftest t=\(step * 2 + 2)s captions=\(captions.count) words=\(totalWords)")
            for caption in captions.suffix(2) {
                let flag = caption.isFinal ? "FINAL" : "PARTIAL"
                log("  [\(flag)] \(caption.source)")
                log("      -> \(caption.target ?? "(none)") state=\(caption.state)")
            }
        }
        await stop()
        log("selftest: done, \(captions.count) captions")
    }
}

private func log(_ message: String) {
    FileHandle.standardError.write(Data(("\(message)\n").utf8))
}
