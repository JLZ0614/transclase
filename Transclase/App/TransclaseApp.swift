import SwiftUI

@main
struct TransclaseApp: App {
    @StateObject private var model = AppModel()

    init() {
        L10n.set(AppSettings.load().appLanguage.localeIdentifier)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
        .defaultSize(width: 880, height: 560)
        .commands {
            CommandMenu(L("课程")) {
                Button(model.isRunning ? L("停止") : L("开始")) {
                    Task { await model.toggle() }
                }
                .keyboardShortcut("r", modifiers: .command)

                Button(L("清空字幕")) {
                    model.requestClear()
                }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(model.captions.isEmpty)
            }
        }
    }
}
