import AVFoundation
import Foundation
import Translation

/// Orchestrates capture → recognition → translation.
///
/// Two channels feed the same transcript:
///  * a **fast channel** that renders volatile recognition text immediately, so
///    the reader keeps up with the lecturer;
///  * a **final channel** that re-translates the settled sentence and replaces
///    the row in place.
/// Rows are keyed by audio timecode, so an update never reorders the list.
@MainActor
final class CaptionPipeline {
    private(set) var captions: [Caption] = []

    var onCaptionsChanged: (([Caption]) -> Void)?
    var onStatus: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onLevel: ((Float) -> Void)?
    var onTranslationEngine: ((String) -> Void)?

    private var settings = AppSettings()
    private var glossary = GlossaryProcessor(terms: [])

    private var audioSource: AudioSource?
    private var asr: ASREngine?
    private var mt: MTEngine?

    private var audioTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var translationTail: Task<Void, Never>?

    private var pendingFinalTranslations = 0
    private var lastDraftAt = Date.distantPast
    private var translationEnabled = true
    /// Bumped per run so ids from a resumed session can't collide with the
    /// rows already on screen (ids are timecode-based and restart at zero).
    private var sessionSeq = 0

    // MARK: - Lifecycle

    func start(
        settings: AppSettings,
        sessionProvider: @escaping () -> TranslationSession?
    ) async throws {
        self.settings = settings
        self.glossary = GlossaryProcessor(terms: settings.glossary)
        // Deliberately does NOT clear: stop/start is pause/resume, not "new
        // lecture". Wiping here loses the transcript on a mis-tapped stop.
        sessionSeq += 1

        onStatus?("正在准备识别模型…")

        let recognizer: ASREngine = settings.demoMode ? DemoASREngine() : AppleSpeechEngine()
        asr = recognizer
        try await recognizer.prepare(locale: LanguageMapping.speechLocale(settings.sourceLanguageID))

        // Pick the best translator this device can actually run right now.
        // A missing language pack must never cost the user the transcript.
        translationEnabled = true
        var useFoundationModel = false
        var engineLabel = "系统离线翻译"

        if settings.demoMode {
            engineLabel = "演示翻译"
        } else {
            let status = await LanguageAvailability().status(
                from: LanguageMapping.translationLanguage(settings.sourceLanguageID),
                to: LanguageMapping.translationLanguage(settings.targetLanguageID)
            )
            if status != .installed {
                if FoundationModelTranslationEngine.isAvailable {
                    useFoundationModel = true
                    engineLabel = "Apple 智能（本地兜底）"
                    onError?("这个语言对的离线语言包还没下载，暂时改用 Apple 智能本地模型翻译。下载语言包后质量会更好。")
                } else {
                    translationEnabled = false
                    engineLabel = "仅原文"
                    onError?("离线语言包没下载，本机也没有可用的 Apple 智能模型，所以先只显示原文。到设置里点“下载语言包”即可开启翻译。")
                }
            }
        }

        onTranslationEngine?(engineLabel)

        let translator: MTEngine
        if settings.demoMode {
            translator = DemoMTEngine()
        } else if useFoundationModel {
            translator = FoundationModelTranslationEngine(
                sourceName: LanguageMapping.displayName(forBCP47: settings.sourceLanguageID),
                targetName: LanguageMapping.promptName(for: settings.targetLanguageID),
                glossary: settings.glossary
            )
        } else {
            translator = AppleTranslationEngine(
                source: LanguageMapping.translationLanguage(settings.sourceLanguageID),
                target: LanguageMapping.translationLanguage(settings.targetLanguageID),
                sessionProvider: sessionProvider
            )
        }
        try await translator.prepare()
        mt = translator

        if !settings.demoMode {
            try await startAudio(into: recognizer)
        }

        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in recognizer.events {
                if Task.isCancelled { break }
                self.handle(event)
            }
        }

        onStatus?("启动中…")
        try await recognizer.start()
        onStatus?(settings.demoMode ? "演示模式运行中" : "正在听课…")
    }

    private func startAudio(into recognizer: ASREngine) async throws {
        let source = MicrophoneSource()
        audioSource = source
        source.onLevel = { [weak self] level in
            Task { @MainActor in self?.onLevel?(level) }
        }

        // Start first: on iOS the input format is only valid once the audio
        // session is active, and reading it earlier yields 0 Hz.
        let stream = try await source.start()

        let inputFormat = source.format
        let wanted = recognizer.requiredFormat
        var converter: BufferConverter?
        if let wanted, wanted != inputFormat {
            guard let made = BufferConverter(from: inputFormat, to: wanted) else {
                throw AudioError.conversionUnavailable
            }
            converter = made
        }

        audioTask = Task.detached(priority: .userInitiated) {
            for await buffer in stream {
                if let converter {
                    if let converted = converter.convert(buffer) {
                        recognizer.append(converted)
                    }
                } else {
                    recognizer.append(buffer)
                }
            }
        }
    }

    func stop() async {
        audioSource?.stop()
        audioSource = nil
        audioTask?.cancel()
        audioTask = nil

        if let asr {
            await asr.stop()
        }
        eventTask?.cancel()
        eventTask = nil

        translationTail?.cancel()
        translationTail = nil
        pendingFinalTranslations = 0
        translationEnabled = true
        asr = nil
        mt = nil
        onLevel?(0)
        onStatus?("已停止")
    }

    // MARK: - Events

    private func handle(_ event: ASREvent) {
        switch event {
        case .partial(let rawID, let text, let start, let end):
            let id = "s\(sessionSeq)-\(rawID)"
            upsert(
                Caption(id: id, source: text, isFinal: false, start: start, end: end)
            )
            maybeDraft(id: id, text: text, start: start, end: end)

        case .final(let rawID, let text, let start, let end):
            let id = "s\(sessionSeq)-\(rawID)"
            upsert(
                Caption(
                    id: id,
                    source: text,
                    isFinal: true,
                    state: translationEnabled ? .pending : .idle,
                    start: start,
                    end: end
                )
            )
            translateFinal(id: id, text: text, start: start, end: end)

        case .status(let message):
            onStatus?(message)

        case .failed(let message):
            onError?(message)
        }
    }

    func clear() {
        captions.removeAll()
        publish()
    }

    private func upsert(_ caption: Caption) {
        if let index = captions.firstIndex(where: { $0.id == caption.id }) {
            var updated = caption
            // While the recognizer is still refining, keep whatever translation
            // we already showed instead of blanking the line.
            if !caption.isFinal {
                updated.target = captions[index].target
                updated.state = captions[index].state
            }
            captions[index] = updated
        } else {
            captions.append(caption)
        }
        publish()
    }

    private func publish() {
        onCaptionsChanged?(captions)
    }

    // MARK: - Translation

    private func translateFinal(id: String, text: String, start: TimeInterval, end: TimeInterval) {
        guard translationEnabled, let mt else { return }
        pendingFinalTranslations += 1
        let previous = translationTail
        translationTail = Task { [weak self] in
            _ = await previous?.value
            guard let self else { return }
            defer { self.pendingFinalTranslations = max(0, self.pendingFinalTranslations - 1) }
            do {
                let raw = try await mt.translate(text)
                let glossed = self.glossary.apply(to: raw, sourceText: text)
                let translated = ChineseVariant.normalized(glossed, for: self.settings.targetLanguageID)
                self.finishTranslation(id: id, text: text, translated: translated)
            } catch {
                self.failTranslation(id: id, text: text, message: error.localizedDescription)
            }
        }
    }

    /// Optional low-latency channel: a rough translation of the words spoken so
    /// far, clearly marked as a draft and replaced once the sentence settles.
    private func maybeDraft(id: String, text: String, start: TimeInterval, end: TimeInterval) {
        guard settings.draftTranslation else { return }
        guard pendingFinalTranslations == 0 else { return }
        guard text.split(whereSeparator: \.isWhitespace).count >= 6 else { return }
        let now = Date()
        guard now.timeIntervalSince(lastDraftAt) > 0.9 else { return }
        guard let mt else { return }
        lastDraftAt = now

        let previous = translationTail
        translationTail = Task { [weak self] in
            _ = await previous?.value
            guard let self else { return }
            guard let raw = try? await mt.translate(text) else { return }
            let glossed = self.glossary.apply(to: raw, sourceText: text)
            let translated = ChineseVariant.normalized(glossed, for: self.settings.targetLanguageID)
            self.applyDraft(id: id, text: text, translated: translated)
        }
    }

    private func finishTranslation(id: String, text: String, translated: String) {
        guard let index = captions.firstIndex(where: { $0.id == id }) else { return }
        guard captions[index].source == text else { return }
        captions[index].target = translated
        captions[index].state = .done
        publish()
    }

    private func failTranslation(id: String, text: String, message: String) {
        guard let index = captions.firstIndex(where: { $0.id == id }) else { return }
        guard captions[index].source == text else { return }
        captions[index].state = .failed(message)
        publish()
        onError?(message)
    }

    private func applyDraft(id: String, text: String, translated: String) {
        guard let index = captions.firstIndex(where: { $0.id == id }) else { return }
        guard !captions[index].isFinal, captions[index].source == text else { return }
        captions[index].target = translated
        captions[index].state = .draft
        publish()
    }
}
