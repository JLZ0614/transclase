import Foundation

/// Canned translations so the app is fully usable without any language packs.
@MainActor
final class DemoMTEngine: MTEngine {
    func prepare() async throws {}

    func translate(_ text: String) async throws -> String {
        try? await Task.sleep(nanoseconds: 140_000_000)
        if let translation = DemoScript.translation(for: text) {
            return translation
        }
        return "（演示翻译）\(text)"
    }
}

