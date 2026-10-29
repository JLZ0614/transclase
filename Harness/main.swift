import Foundation

@main
struct Harness {
    static func main() async {
        await run()
    }

    @MainActor
    static func run() async {
        var settings = AppSettings()
        settings.demoMode = true
        settings.draftTranslation = false

        let pipeline = CaptionPipeline()
        var updates = 0
        pipeline.onCaptionsChanged = { captions in
            updates += 1
            guard let last = captions.last else { return }
            let flag = last.isFinal ? "F" : "P"
            let target = last.target ?? "-"
            print("[\(flag)] \(last.source)\n      => \(target)")
        }
        pipeline.onError = { print("ERROR: \($0)") }

        await runModelScenario()

        print("=== pipeline start ===")
        do {
            try await pipeline.start(settings: settings, sessionProvider: { nil })
        } catch {
            print("START FAILED: \(error)")
            return
        }

        try? await Task.sleep(nanoseconds: 9_000_000_000)
        await pipeline.stop()

        let captions = pipeline.captions
        let finals = captions.filter(\.isFinal)
        let translated = finals.filter { $0.target?.isEmpty == false }
        print("=== result ===")
        print("captions=\(captions.count) finals=\(finals.count) translated=\(translated.count) updates=\(updates)")
        for caption in finals {
            print("\(caption.source)\n  -> \(caption.target ?? "(missing)")")
        }
    }
}
