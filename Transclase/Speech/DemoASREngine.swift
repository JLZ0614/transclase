import AVFoundation
import Foundation

/// Feeds the demo script through the same event vocabulary as the real
/// recognizer, including volatile partials, so the UI behaves identically.
final class DemoASREngine: ASREngine {
    private let eventStream: AsyncStream<ASREvent>
    private let eventContinuation: AsyncStream<ASREvent>.Continuation
    private var task: Task<Void, Never>?
    private var clock: TimeInterval = 0

    var requiredFormat: AVAudioFormat? { nil }
    var events: AsyncStream<ASREvent> { eventStream }

    init() {
        (eventStream, eventContinuation) = AsyncStream<ASREvent>.makeStream(
            bufferingPolicy: .bufferingNewest(32)
        )
    }

    deinit {
        eventContinuation.finish()
    }

    func prepare(locale: Locale) async throws {
        eventContinuation.yield(.status("演示模式"))
    }

    func start() async throws {
        task = Task { [weak self] in
            guard let self else { return }
            var index = 0
            while !Task.isCancelled {
                let line = DemoScript.lines[index % DemoScript.lines.count]
                await self.play(line: line)
                index += 1
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }
    }

    private func play(line: DemoScript.Line) async {
        let words = line.english.split(separator: " ").map(String.init)
        let id = AppleSpeechEngine.captionID(for: clock)
        let segmentStart = clock
        let perWord: UInt64 = 190_000_000

        var buffer: [String] = []
        for word in words {
            if Task.isCancelled { return }
            buffer.append(word)
            let text = buffer.joined(separator: " ")
            eventContinuation.yield(
                .partial(
                    id: id,
                    text: text,
                    start: segmentStart,
                    end: segmentStart + Double(buffer.count)
                )
            )
            try? await Task.sleep(nanoseconds: perWord)
        }

        let duration = Double(words.count) * 0.19
        clock += duration + 0.25
        eventContinuation.yield(
            .final(
                id: id,
                text: line.english,
                start: segmentStart,
                end: segmentStart + duration
            )
        )
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        // Demo mode synthesises its own audio timeline.
    }

    func stop() async {
        task?.cancel()
        task = nil
    }
}
