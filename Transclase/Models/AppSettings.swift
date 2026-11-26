import Foundation

/// Everything the user can tweak. Persisted as JSON in `UserDefaults`.
///
/// Decoding is hand-written so that adding a field in a later version does not
/// wipe the settings of someone upgrading from an older build.
struct AppSettings: Codable, Equatable {
    var sourceLanguageID: String = "en-US"
    var targetLanguageID: String = "zh-Hans"
    var appLanguage: AppLanguage = .system
    var appearance: AppAppearance = .system
    var showOriginal: Bool = true
    /// Apple's `Translation` exposes a fidelity/latency trade-off; high fidelity
    /// reads noticeably better but answers a little slower.
    var highFidelityTranslation: Bool = true
    var fontSize: Double = 16
    var demoMode: Bool = false
    /// Voice-notes mode: transcribe only, never translate.
    var transcriptionOnly: Bool = false
    var autoScroll: Bool = true

    // Translation backend
    var translationEngine: TranslationEngineKind = .apple
    var cloudBaseURL: String = "https://api.deepseek.com/v1"
    var cloudModel: String = "deepseek-chat"

    // Model providers (the「模型」pane manages this list)
    var providers: [ModelProvider] = [.preset()]
    var activeProviderID: UUID?

    // Assistant
    var assistantEnabled: Bool = false
    var summaryIntervalMinutes: Int = 5

    private static let storageKey = "transclase.settings.v1"

    init() {}

    private enum CodingKeys: String, CodingKey {
        case sourceLanguageID, targetLanguageID, showOriginal, highFidelityTranslation, fontSize, demoMode, transcriptionOnly, autoScroll
        case translationEngine, cloudBaseURL, cloudModel
        case providers, activeProviderID, appLanguage, appearance
        case assistantEnabled, summaryIntervalMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        sourceLanguageID = try c.decodeIfPresent(String.self, forKey: .sourceLanguageID) ?? d.sourceLanguageID
        targetLanguageID = try c.decodeIfPresent(String.self, forKey: .targetLanguageID) ?? d.targetLanguageID
        showOriginal = try c.decodeIfPresent(Bool.self, forKey: .showOriginal) ?? d.showOriginal
        highFidelityTranslation = try c.decodeIfPresent(Bool.self, forKey: .highFidelityTranslation) ?? d.highFidelityTranslation
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? d.fontSize
        demoMode = try c.decodeIfPresent(Bool.self, forKey: .demoMode) ?? d.demoMode
        transcriptionOnly = try c.decodeIfPresent(Bool.self, forKey: .transcriptionOnly) ?? d.transcriptionOnly
        autoScroll = try c.decodeIfPresent(Bool.self, forKey: .autoScroll) ?? d.autoScroll
        // Unknown / removed engines (e.g. the old local Qwen3) fall back to the
        // system translator instead of failing the whole settings decode.
        let rawEngine = try c.decodeIfPresent(String.self, forKey: .translationEngine)
        translationEngine = rawEngine.flatMap(TranslationEngineKind.init(rawValue:)) ?? d.translationEngine
        cloudBaseURL = try c.decodeIfPresent(String.self, forKey: .cloudBaseURL) ?? d.cloudBaseURL
        cloudModel = try c.decodeIfPresent(String.self, forKey: .cloudModel) ?? d.cloudModel
        appLanguage = try c.decodeIfPresent(AppLanguage.self, forKey: .appLanguage) ?? d.appLanguage
        appearance = try c.decodeIfPresent(AppAppearance.self, forKey: .appearance) ?? d.appearance
        providers = try c.decodeIfPresent([ModelProvider].self, forKey: .providers) ?? d.providers
        activeProviderID = try c.decodeIfPresent(UUID.self, forKey: .activeProviderID) ?? d.activeProviderID
        assistantEnabled = try c.decodeIfPresent(Bool.self, forKey: .assistantEnabled) ?? d.assistantEnabled
        summaryIntervalMinutes = try c.decodeIfPresent(Int.self, forKey: .summaryIntervalMinutes) ?? d.summaryIntervalMinutes
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
