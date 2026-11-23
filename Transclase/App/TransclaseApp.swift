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
        #if os(macOS)
        .defaultSize(width: 880, height: 560)
        #endif
    }
}
