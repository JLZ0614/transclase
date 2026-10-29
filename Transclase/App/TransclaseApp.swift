import SwiftUI

@main
struct TransclaseApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
        #if os(macOS)
        .commands {
            CommandMenu("课程") {
                Button(model.isRunning ? "停止" : "开始") {
                    Task { await model.toggle() }
                }
                .keyboardShortcut("r", modifiers: .command)

                Button("清空字幕") {
                    model.requestClear()
                }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(model.captions.isEmpty)
            }
        }
        #endif
    }
}
