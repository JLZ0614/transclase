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
    var onSpeechDownloadProgress: ((Double) -> Void)?

    private var settings = AppSettings()

    private var audioSource: AudioSource?
    private var asr: ASREngine?
    private var mt: MTEngine?

    private var audioTask: Task<Void, Never>?
    private var eventTask: Task<Void, Never>?
    private var translationTail: Task<Void, Never>?

    private var pendingFinalTranslations = 0

    // Sentence assembly: fragments are merged until a boundary, a pause, or a
    // length cap closes the sentence, then translated as a whole.
    private var sentenceID: String?
    private var sentenceText = ""
    private var sentenceStart: TimeInterval = 0
    private var sentenceEnd: TimeInterval = 0
    private var flushTask: Task<Void, Never>?
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
        // Deliberately does NOT clear: stop/start is pause/resume, not "new
        // lecture". Wiping here loses the transcript on a mis-tapped stop.
        sessionSeq += 1

        onStatus?(L("正在准备识别模型…"))

        let recognizer: ASREngine = settings.demoMode ? DemoASREngine() : AppleSpeechEngine()
        if let apple = recognizer as? AppleSpeechEngine {
            apple.onDownloadProgress = { [weak self] fraction in
                Task { @MainActor in self?.onSpeechDownloadProgress?(fraction) }
            }
        }
        asr = recognizer
        try await recognizer.prepare(locale: LanguageMapping.speechLocale(settings.sourceLanguageID))

        // Pick a translator. The user's choice wins; if it cannot start we fall
        // back to Apple's on-device engine rather than losing translation.
        translationEnabled = true
        var engineLabel = L("系统离线翻译")
        var translator: MTEngine

        if settings.demoMode {
            engineLabel = L("演示翻译")
            translator = DemoMTEngine()
        } else {
            let sourceName = LanguageMapping.displayName(forBCP47: settings.sourceLanguageID)
            let targetName = LanguageMapping.promptName(for: settings.targetLanguageID)

            switch settings.translationEngine {
            case .apple:
                (translator, engineLabel, translationEnabled) = await Self.appleTranslator(
                    settings: settings,
                    sourceName: sourceName,
                    targetName: targetName,
                    sessionProvider: sessionProvider,
                    onError: onError
                )

            case .localQwen, .cloud:
                let isCloud = settings.translationEngine == .cloud
                let provider = settings.providers.first { $0.id == settings.activeProviderID } ?? settings.providers.first
                let urlString = isCloud ? (provider?.baseURL ?? "") : settings.localBaseURL
                let model = isCloud ? (provider?.model ?? "") : settings.localModel
                let key = isCloud ? provider.flatMap { CredentialStore.load("provider.\($0.id.uuidString)") } : nil
                let label = isCloud ? "云端 · \(model)" : "本地 · \(model)"

                if let url = URL(string: urlString) {
                    let candidate = OpenAICompatibleEngine(
                        baseURL: url,
                        model: model,
                        apiKey: key,
                        sourceName: sourceName,
                        targetName: targetName
                    )
                    do {
                        try await candidate.prepare()
                        translator = candidate
                        engineLabel = label
                    } catch {
                        onError?("\(label) 不可用（\(error.localizedDescription)），已临时改用系统翻译。")
                        (translator, engineLabel, translationEnabled) = await Self.appleTranslator(
                            settings: settings,
                            sourceName: sourceName,
                            targetName: targetName,
                            sessionProvider: sessionProvider,
                            onError: nil
                        )
                    }
                } else {
                    onError?(L("翻译引擎地址无效，已改用系统翻译。"))
                    (translator, engineLabel, translationEnabled) = await Self.appleTranslator(
                        settings: settings,
                        sourceName: sourceName,
                        targetName: targetName,
                        sessionProvider: sessionProvider,
                        onError: nil
                    )
                }
            }
        }

        onTranslationEngine?(engineLabel)
        if !(translator is AppleTranslationEngine) {
            try await translator.prepare()
        }
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

        onStatus?(L("启动中…"))
        try await recognizer.start()
        onStatus?(settings.demoMode ? L("演示模式运行中") : L("正在听课…"))
    }

    /// Apple's on-device path, including the language-pack check and the Apple
    /// Intelligence fallback. Returns the engine, its label, and whether
    /// translation should be attempted at all.
    private static func appleTranslator(
        settings: AppSettings,
        sourceName: String,
        targetName: String,
        sessionProvider: @escaping () -> TranslationSession?,
        onError: ((String) -> Void)?
    ) async -> (MTEngine, String, Bool) {
        let source = LanguageMapping.translationLanguage(settings.sourceLanguageID)
        let target = LanguageMapping.translationLanguage(settings.targetLanguageID)
        let status = await LanguageAvailability().status(from: source, to: target)

        if status == .installed {
            return (
                AppleTranslationEngine(source: source, target: target, sessionProvider: sessionProvider),
                L("系统离线翻译"),
                true
            )
        }

        onError?(L("离线语言包还没下载，先只显示原文。到设置里点“下载语言包”即可开启翻译。"))
        return (
            AppleTranslationEngine(source: source, target: target, sessionProvider: sessionProvider),
            L("仅原文"),
            false
        )
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
        finalizeSentence()
        eventTask?.cancel()
        eventTask = nil

        translationTail?.cancel()
        translationTail = nil
        pendingFinalTranslations = 0
        translationEnabled = true
        asr = nil
        mt = nil
        onLevel?(0)
        onStatus?(L("已停止"))
    }

    // MARK: - Events

    private func handle(_ event: ASREvent) {
        switch event {
        case .partial(let rawID, let text, let start, let end):
            let id = "s\(sessionSeq)-\(rawID)"
            if sentenceID == nil {
                // Nothing buffered yet: this row will become the sentence row.
                upsert(Caption(id: id, source: text, isFinal: false, start: start, end: end))
            } else if let sentenceID {
                // Prepend what we already have so the line reads continuously.
                upsert(
                    Caption(
                        id: sentenceID,
                        source: sentenceText + " " + text,
                        isFinal: false,
                        start: sentenceStart,
                        end: end
                    )
                )
            }

        case .final(let rawID, let text, let start, let end):
            let id = "s\(sessionSeq)-\(rawID)"
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return }

            // A long pause means the previous sentence is done even without
            // punctuation.
            if sentenceID != nil, start - sentenceEnd > 0.6 {
                finalizeSentence()
            }

            if sentenceID == nil {
                sentenceID = id            // reuse the live row, no flicker
                sentenceText = clean
                sentenceStart = start
            } else {
                captions.removeAll { $0.id == id }   // drop its transient row
                sentenceText += " " + clean
            }
            sentenceEnd = end

            if let sentenceID {
                upsert(
                    Caption(
                        id: sentenceID,
                        source: sentenceText,
                        isFinal: false,
                        start: sentenceStart,
                        end: end
                    )
                )
            }

            if SentenceRules.endsSentence(sentenceText) || SentenceRules.tooLong(sentenceText) {
                finalizeSentence()
            } else {
                scheduleFlush()
            }

        case .status(let message):
            onStatus?(message)

        case .failed(let message):
            onError?(message)
        }
    }

    /// Closes the current sentence: marks the row final and translates the whole
    /// thing at once.
    private func finalizeSentence() {
        flushTask?.cancel()
        flushTask = nil
        guard let id = sentenceID else { return }
        let text = sentenceText.trimmingCharacters(in: .whitespacesAndNewlines)
        sentenceID = nil
        sentenceText = ""
        guard !text.isEmpty else { return }

        upsert(
            Caption(
                id: id,
                source: text,
                isFinal: true,
                state: translationEnabled ? .pending : .idle,
                start: sentenceStart,
                end: sentenceEnd
            )
        )
        translateFinal(id: id, text: text, start: sentenceStart, end: sentenceEnd)
    }

    /// Flushes a sentence that ended at a pause without terminal punctuation.
    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_300_000_000)
            guard !Task.isCancelled else { return }
            self?.finalizeSentence()
        }
    }

    /// Replaces the buffer with a restored transcript (opening a past lecture)
    /// so continued recording appends instead of starting from empty.
    func load(_ restored: [Caption]) {
        flushTask?.cancel()
        flushTask = nil
        sentenceID = nil
        sentenceText = ""
        captions = restored
        publish()
    }

    func clear() {
        flushTask?.cancel()
        flushTask = nil
        sentenceID = nil
        sentenceText = ""
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
                let translated = ChineseVariant.normalized(raw, for: self.settings.targetLanguageID)
                self.finishTranslation(id: id, text: text, translated: translated)
            } catch {
                self.failTranslation(id: id, text: text, message: error.localizedDescription)
            }
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

}
