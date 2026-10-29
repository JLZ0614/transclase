import Foundation

/// Exercises the same state machine the buttons drive: start → captions →
/// clear → stop → restart. Catches re-entrancy bugs that a UI click would hit.
@MainActor
func runModelScenario() async {
    print("=== model scenario ===")
    let model = AppModel()
    model.settings.demoMode = true

    print("initial: running=\(model.isRunning) preparing=\(model.isPreparing) captions=\(model.captions.count)")

    await model.start()
    try? await Task.sleep(nanoseconds: 6_000_000_000)
    print("after start: running=\(model.isRunning) captions=\(model.captions.count) engine=\(model.translationEngineLabel)")

    model.requestClear()
    print("clear confirm requested: \(model.pendingClearConfirmation)")
    model.clear()
    print("after clear: captions=\(model.captions.count) confirm=\(model.pendingClearConfirmation) markdownEmpty=\(model.translationMarkdown.isEmpty)")

    await model.stop()
    print("after stop: running=\(model.isRunning) preparing=\(model.isPreparing) level=\(model.level)")

    await model.start()
    try? await Task.sleep(nanoseconds: 5_000_000_000)
    print("restart: running=\(model.isRunning) captions=\(model.captions.count) (should be >= 2: paused session resumes, not wiped)")

    await model.stop()
    print("final: running=\(model.isRunning) captions=\(model.captions.count)")
    print("=== model scenario done ===")
}
