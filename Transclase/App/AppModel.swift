import AppKit
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
    @Published var statusText = L("就绪")
    @Published var errorMessage: String?
    @Published var level: Float = 0
    @Published var scrollGeneration = 0
    @Published var isPinnedToBottom = true
    @Published var startedAt: Date?
    @Published var translationConfiguration: TranslationSession.Configuration?
    @Published var translationNote: String?
    @Published var translationEngineLabel = "—"
    @Published var languagePackStatus = L("未知")
    @Published var pendingClearConfirmation = false
    @Published var speechProgress: Double?
    @Published var isPreparingPack = false
    @Published var sessions: [LectureSession] = []
    @Published var currentSession: LectureSession?
    @Published var summaries: [SummaryBlock] = []
    @Published var assistantBusy = false
    @Published var assistantError: String?
    @Published var chat: [AssistantTurn] = []
    @Published var providerModels: [String] = []
    @Published var isLoadingModels = false
    @Published var modelListError: String?
    /// Changes whenever the interface language changes, so the view tree can be
    /// rebuilt without relaunching.
    @Published var localizationToken = UUID()
    @Published var isFullScreen = false
    @Published var windowSize: CGSize = CGSize(width: 1200, height: 860)
    @Published var menusNeedRelaunch = false
    /// Language the process actually started with; the menu bar is frozen to it.
    private let launchLanguage = AppSettings.load().appLanguage
    @Published var engineTestResult: String? 
    @Published var isTestingEngine = false
    @Published var exportDocument: MarkdownDocument?
    @Published var isExporting = false
    @Published var isBootstrapping = true
    @Published var speechOptions: [LanguageOption] = []
    @Published var translationOptions: [LanguageOption] = []

    private let pipeline = CaptionPipeline()
    private var markdownCache: (stamp: Int, text: String) = (-1, "")
    private var transientDemo = false
    private var summaryTask: Task<Void, Never>?
    private var summarizedCaptionCount = 0
    private var persistedFinalCount = 0
    private var hasTranscriptHeader = false
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

    /// L("看演示") must not flip a persisted setting — otherwise the app stays in
    /// fake-lecture mode forever and the next real session is nonsense.
    func playDemo() async {
        transientDemo = true
        await start()
    }


    /// Recognition model for the chosen source locale is on disk.
    var isSpeechModelInstalled: Bool {
        speechOptions.first { $0.id == settings.sourceLanguageID }?.isInstalled ?? false
    }

    var isTranslationPackInstalled: Bool { languagePackStatus == L("已安装") }

    /// Everything needed to work with no network and no further downloads.
    var isReadyOffline: Bool {
        guard !isDemoActive else { return true }
        return isSpeechModelInstalled && isTranslationPackInstalled
    }

    var speechLanguages: Set<String> { Set(speechOptions.map(\.id)) }
    var translationLanguages: Set<String> { Set(translationOptions.map(\.id)) }

    func bootstrap() async {
        applyStoredLanguage()
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
            languagePackStatus = L("演示模式无需语言包")
            return
        }
        let status = await LanguageAvailability().status(
            from: LanguageMapping.translationLanguage(settings.sourceLanguageID),
            to: LanguageMapping.translationLanguage(settings.targetLanguageID)
        )
        switch status {
        case .installed:
            languagePackStatus = L("已安装")
        case .supported:
            languagePackStatus = L("未下载")
        default:
            languagePackStatus = L("不支持该语言对")
        }
    }

    /// Bumps the configuration so `.translationTask` re-runs and the system
    /// download prompt appears for the current pair.
    func downloadLanguagePack() async {
        guard !isRunning else { return }
        syncTranslationConfiguration(force: true)
        try? await Task.sleep(for: .seconds(3))
        await refreshLanguagePackStatus()
        if languagePackStatus != L("已安装") {
            translationNote = L("没看到下载面板的话，去 系统设置 → 通用 → 语言与地区 → 翻译语言，手动添加该语言。")
        } else {
            translationNote = L("语言包已安装，重启一次识别后生效。")
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
                self.translationNote = L("语言包已就绪（全程离线）")
            case .supported:
                self.translationNote = L("语言包尚未下载：点上面的按钮，在系统面板里确认下载")
            default:
                self.translationNote = L("这台设备不支持这个语言对")
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

    // MARK: - Translation engine


    /// Sends one throw-away sentence through the selected engine so the user can
    /// tell "config wrong" from "model slow".
    func testTranslationEngine() async {
        guard !isTestingEngine else { return }
        isTestingEngine = true
        engineTestResult = nil
        defer { isTestingEngine = false }

        let s = settings
        let isCloud = s.translationEngine == .cloud
        let provider = activeProvider
        let urlString = isCloud ? (provider?.baseURL ?? "") : s.localBaseURL
        let model = isCloud ? (provider?.model ?? "") : s.localModel
        guard let url = URL(string: urlString) else {
            engineTestResult = L("地址无效")
            return
        }

        let engine = OpenAICompatibleEngine(
            baseURL: url,
            model: model,
            apiKey: isCloud ? provider.flatMap { providerKey($0) } : nil,
            sourceName: LanguageMapping.displayName(forBCP47: s.sourceLanguageID),
            targetName: LanguageMapping.promptName(for: s.targetLanguageID)
        )
        let started = Date()
        do {
            try await engine.prepare()
            let output = try await engine.translate("This is a test of the translation engine.")
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            engineTestResult = "✅ \(ms) ms · \(output)"
        } catch {
            engineTestResult = "❌ \(error.localizedDescription)"
        }
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
            if currentSession == nil { currentSession = SessionStore.create() }
            refreshSessions()
            startSummaryTimer()
        } catch {
            await pipeline.stop()
            errorMessage = error.localizedDescription
            statusText = L("启动失败")
            isRunning = false
        }
    }

    func stop() async {
        guard isRunning else { return }
        await pipeline.stop()
        isRunning = false
        level = 0
        transientDemo = false
        stopSummaryTimer()
        persistTranscript()
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
        // Summaries describe captions that no longer exist.
        summarizedCaptionCount = 0
        persistedFinalCount = 0
        summaries = []
        chat = []
    }

    func saveSettings() {
        settings.save()
    }

    /// Applies a language change and restarts, the only way AppKit will rebuild
    /// its menus in the new language.
    /// Reconciles AppleLanguages with the stored choice, so a leftover override
    /// cannot survive after switching back to "follow system".
    func applyStoredLanguage() {
        settings.appLanguage.apply()
        L10n.set(settings.appLanguage.localeIdentifier)
    }

    /// Switches the interface language immediately. The macOS menu bar keeps the
    /// old language until the next launch — AppKit builds it once.
    func switchLanguage(_ language: AppLanguage) {
        L10n.set(language.localeIdentifier)
        localizationToken = UUID()
        // The menu bar only matches after a relaunch, whatever the target is.
        menusNeedRelaunch = language != launchLanguage
    }

    func relaunch() {
        let url = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                guard error == nil else {
                    self.errorMessage = L("重启失败，请手动退出后重新打开")
                    return
                }
                NSApp.terminate(nil)
            }
        }
    }

    // MARK: - Sessions

    /// Writes the finished transcript into the session markdown file.
    private func persistTranscript() {
        guard let session = currentSession else { return }
        let finals = Array(captions.filter(\.isFinal).dropFirst(persistedFinalCount))
        guard !finals.isEmpty else { return }
        persistedFinalCount += finals.count
        var body = hasTranscriptHeader ? "\n" : "\n## 逐字稿\n\n"
        hasTranscriptHeader = true
        for caption in finals {
            body += "**[\(SessionExport.timecode(caption.start))]**\n\n> \(caption.source)\n\n"
            if let target = caption.target, !target.isEmpty {
                body += "\(target)\n\n"
            }
        }
        SessionStore.append(body, to: session)
    }

    func refreshSessions() {
        sessions = SessionStore.list()
    }

    /// Starts a new lecture: fresh captions, fresh markdown document.
    func newConversation() async {
        // Stop first: the previous lecture's transcript is written during stop,
        // and clearing before that would lose it.
        if isRunning { await stop() }
        pipeline.clear()

        let session = SessionStore.create()
        currentSession = session
        summaries = []
        chat = []
        summarizedCaptionCount = 0
        persistedFinalCount = 0
        hasTranscriptHeader = false
        assistantError = nil
        captions.removeAll()
        startedAt = nil
        refreshSessions()
    }

    /// Single click in the workspace: load that lecture so it can be reviewed or
    /// continued. New captions are appended to the same document.
    func openSession(_ session: LectureSession) async {
        if isRunning { await stop() }
        let loaded = SessionStore.load(session)
        pipeline.load(loaded.captions)
        captions = loaded.captions
        summaries = loaded.summaries
        chat = []
        currentSession = session
        summarizedCaptionCount = loaded.captions.count
        persistedFinalCount = loaded.captions.count
        hasTranscriptHeader = SessionStore.read(session).contains("## 逐字稿")
        startedAt = nil
        assistantError = nil
        markdownCache = (-1, "")
        refreshSessions()
    }

    func openInFinder(_ session: LectureSession) {
        NSWorkspace.shared.activateFileViewerSelecting([session.url])
    }

    // MARK: - Assistant

    var activeProvider: ModelProvider? {
        settings.providers.first { $0.id == settings.activeProviderID } ?? settings.providers.first
    }

    func updateProvider(_ id: UUID, mutate: (inout ModelProvider) -> Void) {
        guard let index = settings.providers.firstIndex(where: { $0.id == id }) else { return }
        mutate(&settings.providers[index])
    }

    func loadModels(for provider: ModelProvider) async {
        guard let url = URL(string: provider.baseURL) else { return }
        isLoadingModels = true
        modelListError = nil
        defer { isLoadingModels = false }
        do {
            let ids = try await LLMClient(
                baseURL: url,
                model: provider.model,
                apiKey: providerKey(provider)
            ).listModels()
            providerModels = ids
            if !ids.contains(provider.model) {
                modelListError = L("当前模型不在列表里，仍可手动填写。")
            }
        } catch {
            providerModels = []
            modelListError = "拉取失败：\(error.localizedDescription)"
        }
    }

    func providerKey(_ provider: ModelProvider) -> String? {
        CredentialStore.load("provider.\(provider.id.uuidString)")
    }

    func saveProviderKey(_ provider: ModelProvider, key: String) {
        CredentialStore.save(key, for: "provider.\(provider.id.uuidString)")
    }

    private func assistantClient() -> LLMClient? {
        guard let provider = activeProvider, let url = URL(string: provider.baseURL) else { return nil }
        guard let key = providerKey(provider) else {
            assistantError = "先在「模型」里给 \(provider.name) 填入 API Key，助手才能工作。"
            return nil
        }
        return LLMClient(baseURL: url, model: provider.model, apiKey: key)
    }

    private var assistantLanguage: String {
        settings.targetLanguageID.hasPrefix("zh") ? "Simplified Chinese" : "the target language"
    }

    private func transcript(since index: Int, limit: Int = 400) -> (text: String, range: String) {
        let finals = captions.filter(\.isFinal)
        let slice = finals.dropFirst(index).suffix(limit)
        let text = slice
            .map { "[\(SessionExport.timecode($0.start))] \($0.source)" }
            .joined(separator: "\n")
        let start = slice.first.map { SessionExport.timecode($0.start) } ?? "00:00"
        let end = slice.last.map { SessionExport.timecode($0.end) } ?? "00:00"
        return (text, "\(start)–\(end)")
    }

    func summarizeNow() async {
        guard !assistantBusy else { return }
        guard let client = assistantClient() else { return }

        let (text, range) = transcript(since: summarizedCaptionCount)
        guard !text.isEmpty else {
            assistantError = L("还没有可总结的内容。")
            return
        }

        assistantBusy = true
        assistantError = nil
        defer { assistantBusy = false }

        do {
            let markdown = try await client.complete(
                messages: AssistantPrompts.summary(transcript: text, targetLanguage: assistantLanguage)
            )
            let block = SummaryBlock(createdAt: Date(), range: range, markdown: markdown)
            summaries.append(block)
            summarizedCaptionCount = captions.filter(\.isFinal).count

            if let session = currentSession {
                SessionStore.append("\n## 要点 \(range)\n\n\(markdown)\n", to: session)
            }
        } catch {
            assistantError = error.localizedDescription
        }
    }

    func ask(_ question: String) async {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let client = assistantClient() else { return }

        chat.append(AssistantTurn(isUser: true, text: trimmed))
        assistantBusy = true
        assistantError = nil
        defer { assistantBusy = false }

        let (text, _) = transcript(since: 0, limit: 300)
        do {
            let answer = try await client.complete(
                messages: AssistantPrompts.answer(
                    question: trimmed,
                    transcript: text,
                    targetLanguage: assistantLanguage
                )
            )
            chat.append(AssistantTurn(isUser: false, text: answer))
        } catch {
            assistantError = error.localizedDescription
        }
    }

    func refreshSummaryTimer() {
        guard isRunning else { return }
        startSummaryTimer()
    }

    func startSummaryTimer() {
        summaryTask?.cancel()
        guard settings.assistantEnabled else { return }
        let seconds = UInt64(max(1, min(10, settings.summaryIntervalMinutes))) * 60
        summaryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
                guard !Task.isCancelled else { break }
                await self?.summarizeNow()
            }
        }
    }

    func stopSummaryTimer() {
        summaryTask?.cancel()
        summaryTask = nil
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
