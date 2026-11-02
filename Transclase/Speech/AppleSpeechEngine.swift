import AVFoundation
import Foundation
import Speech

/// Apple's on-device `SpeechAnalyzer` / `SpeechTranscriber`, the same model
/// stack that powers Notes and Voice Memos. It is purpose-built for long-form,
/// distant audio such as lectures, and it is free and private.
final class AppleSpeechEngine: ASREngine {
    private let eventStream: AsyncStream<ASREvent>
    private let eventContinuation: AsyncStream<ASREvent>.Continuation

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?

    private(set) var requiredFormat: AVAudioFormat?

    /// 0…1 while the system is fetching the recognition model.
    var onDownloadProgress: ((Double) -> Void)?

    var events: AsyncStream<ASREvent> { eventStream }

    static func makeTranscriber(locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: [.audioTimeRange, .transcriptionConfidence]
        )
    }

    init() {
        (eventStream, eventContinuation) = AsyncStream<ASREvent>.makeStream(
            bufferingPolicy: .bufferingNewest(32)
        )
    }

    deinit {
        eventContinuation.finish()
    }

    func prepare(locale: Locale) async throws {
        guard SpeechTranscriber.isAvailable else { throw ASRError.unavailable }

        guard let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) else {
            throw ASRError.unsupportedLocale(locale.identifier)
        }

        let transcriber = Self.makeTranscriber(locale: supported)
        self.transcriber = transcriber

        try await ensureModel(for: transcriber, locale: supported)

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer

        // Let the framework decide the cheapest format it can consume directly.
        requiredFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]
        )
    }

    private func ensureModel(for transcriber: SpeechTranscriber, locale: Locale) async throws {
        let alreadyInstalled = await SpeechTranscriber.installedLocales
            .map { $0.identifier(.bcp47) }
            .contains(locale.identifier(.bcp47))
        guard !alreadyInstalled else { return }

        eventContinuation.yield(.status("正在下载 \(languageName(locale)) 识别模型…"))
        do {
            try await SpeechModelInstaller.ensureInstalled(
                module: transcriber,
                locale: locale
            ) { [weak self] fraction in
                self?.onDownloadProgress?(fraction)
            }
        } catch {
            throw ASRError.modelDownloadFailed(error.localizedDescription)
        }
    }

    func start() async throws {
        guard let analyzer, let transcriber else {
            throw ASRError.engineFailed("识别器尚未准备")
        }

        let (inputStream, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
        self.inputContinuation = inputContinuation

        resultsTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { continue }

                    let start = result.range.start.seconds
                    let end = result.range.end.seconds
                    let id = Self.captionID(for: start)
                    let event: ASREvent = result.isFinal
                        ? .final(id: id, text: text, start: start, end: end)
                        : .partial(id: id, text: text, start: start, end: end)
                    self.eventContinuation.yield(event)
                }
            } catch {
                self.eventContinuation.yield(.failed(error.localizedDescription))
            }
        }

        try await analyzer.start(inputSequence: inputStream)
        eventContinuation.yield(.status("识别中"))
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        inputContinuation?.yield(AnalyzerInput(buffer: buffer))
    }

    func stop() async {
        inputContinuation?.finish()
        inputContinuation = nil

        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        // Drain the last finalized segment, but never block shutdown forever.
        await waitForResults()
        resultsTask = nil
        analyzer = nil
        transcriber = nil
    }

    private func waitForResults(timeout: Duration = .seconds(3)) async {
        guard let task = resultsTask else { return }
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await task.value }
            group.addTask { try? await Task.sleep(for: timeout) }
            await group.next()
            group.cancelAll()
        }
    }

    private func languageName(_ locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
    }

    /// Stable row identity from the audio timecode. Volatile results for the
    /// same span map to the same row, so text is replaced rather than appended.
    static func captionID(for time: TimeInterval) -> String {
        "seg-\(Int((time * 10).rounded()))"
    }
}


/// Downloads the on-device recognition model for a locale, reporting progress.
/// Shared by the engine (implicit download on start) and by the app's explicit
/// "prepare offline pack" flow.
enum SpeechModelInstaller {
    static func ensureInstalled(
        module: SpeechTranscriber,
        locale: Locale,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws {
        let installed = await SpeechTranscriber.installedLocales
            .map { $0.identifier(.bcp47) }
        if installed.contains(locale.identifier(.bcp47)) {
            onProgress?(1)
            return
        }

        _ = try? await AssetInventory.reserve(locale: locale)
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) else {
            onProgress?(1)
            return
        }

        // `Progress` is only observable through polling here; 200 ms is smooth
        // enough for a progress bar and cheap enough to ignore.
        let poller = onProgress.map { report in
            Task {
                while !Task.isCancelled {
                    report(request.progress.fractionCompleted)
                    if request.progress.isFinished { break }
                    try? await Task.sleep(nanoseconds: 200_000_000)
                }
            }
        }
        defer { poller?.cancel() }

        try await request.downloadAndInstall()
        onProgress?(1)
    }
}
