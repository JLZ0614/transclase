import Foundation

/// One OpenAI-compatible provider entry. The API key lives in CredentialStore,
/// keyed by `provider.<id>`, so the list itself stays non-secret.
struct ModelProvider: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String = "DeepSeek"
    var baseURL: String = "https://api.deepseek.com/v1"
    /// Currently selected model.
    var model: String = "deepseek-chat"
    /// Every model the user keeps for this provider; the picker shows these.
    var models: [String] = ["deepseek-chat"]
    /// Where the user creates an API key, shown as a link.
    var apiKeyURL: String = ""

    init(
        id: UUID = UUID(),
        name: String,
        baseURL: String,
        model: String,
        models: [String] = [],
        apiKeyURL: String = ""
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.model = model
        // A custom provider starts empty until the user adds a model name;
        // forcing an empty-string entry made the editor look broken.
        if models.isEmpty, !model.isEmpty {
            self.models = [model]
        } else {
            self.models = models
        }
        if !model.isEmpty, !self.models.contains(model) { self.models.insert(model, at: 0) }
        self.apiKeyURL = apiKeyURL
    }

    // Tolerate settings written before `models` / `apiKeyURL` existed.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "DeepSeek"
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        apiKeyURL = try container.decodeIfPresent(String.self, forKey: .apiKeyURL) ?? ""
        let stored = try container.decodeIfPresent([String].self, forKey: .models) ?? []
        models = stored
        if models.isEmpty, !model.isEmpty { models = [model] }
        if !model.isEmpty, !models.contains(model) { models.insert(model, at: 0) }
    }

    static func preset() -> ModelProvider {
        make(from: ProviderPreset.all[0])
    }

    static func make(from preset: ProviderPreset) -> ModelProvider {
        ModelProvider(
            name: preset.name,
            baseURL: preset.baseURL,
            model: preset.models.first ?? "",
            models: preset.models,
            apiKeyURL: preset.apiKeyURL
        )
    }
}
