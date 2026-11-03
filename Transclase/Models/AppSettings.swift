import Foundation

/// Everything the user can tweak. Persisted as JSON in `UserDefaults`.
///
/// Decoding is hand-written so that adding a field in a later version does not
/// wipe the settings of someone upgrading from an older build.
struct AppSettings: Codable, Equatable {
    var sourceLanguageID: String = "en-US"
    var targetLanguageID: String = "zh-Hans"
    var showOriginal: Bool = true
    var fontSize: Double = 24
    var demoMode: Bool = false
    var autoScroll: Bool = true

    // Translation backend
    var translationEngine: TranslationEngineKind = .apple
    var localBaseURL: String = "http://127.0.0.1:11434/v1"
    var localModel: String = "qwen3:4b"
    var cloudBaseURL: String = "https://api.deepseek.com/v1"
    var cloudModel: String = "deepseek-chat"

    private static let storageKey = "transclase.settings.v1"

    init() {}

    private enum CodingKeys: String, CodingKey {
        case sourceLanguageID, targetLanguageID, showOriginal, fontSize, demoMode, autoScroll
        case translationEngine, localBaseURL, localModel, cloudBaseURL, cloudModel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        sourceLanguageID = try c.decodeIfPresent(String.self, forKey: .sourceLanguageID) ?? d.sourceLanguageID
        targetLanguageID = try c.decodeIfPresent(String.self, forKey: .targetLanguageID) ?? d.targetLanguageID
        showOriginal = try c.decodeIfPresent(Bool.self, forKey: .showOriginal) ?? d.showOriginal
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? d.fontSize
        demoMode = try c.decodeIfPresent(Bool.self, forKey: .demoMode) ?? d.demoMode
        autoScroll = try c.decodeIfPresent(Bool.self, forKey: .autoScroll) ?? d.autoScroll
        translationEngine = try c.decodeIfPresent(TranslationEngineKind.self, forKey: .translationEngine) ?? d.translationEngine
        localBaseURL = try c.decodeIfPresent(String.self, forKey: .localBaseURL) ?? d.localBaseURL
        localModel = try c.decodeIfPresent(String.self, forKey: .localModel) ?? d.localModel
        cloudBaseURL = try c.decodeIfPresent(String.self, forKey: .cloudBaseURL) ?? d.cloudBaseURL
        cloudModel = try c.decodeIfPresent(String.self, forKey: .cloudModel) ?? d.cloudModel
    }

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
