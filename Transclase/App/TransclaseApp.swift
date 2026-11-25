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
        .defaultSize(width: 1180, height: 760)
        #endif
    }
}
