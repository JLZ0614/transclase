import Foundation

/// Everything the user can tweak. Persisted as JSON in `UserDefaults`.
struct AppSettings: Codable, Equatable {
    var sourceLanguageID: String = "en-US"
    var targetLanguageID: String = "zh-Hans"
    var showOriginal: Bool = true
    var fontSize: Double = 24
    var draftTranslation: Bool = false
    var demoMode: Bool = false
    var autoScroll: Bool = true
    var glossary: [GlossaryTerm] = GlossaryTerm.samples

    private static let storageKey = "transclase.settings.v1"

    static func load() -> AppSettings {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return AppSettings()
        }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
