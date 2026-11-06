import Foundation

/// One OpenAI-compatible provider entry. The API key lives in CredentialStore,
/// keyed by `provider.<id>`, so the list itself stays non-secret.
struct ModelProvider: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var name: String = L("新服务商")
    var baseURL: String = "https://api.deepseek.com/v1"
    var model: String = "deepseek-chat"

    static func preset() -> ModelProvider {
        ModelProvider(name: "DeepSeek", baseURL: "https://api.deepseek.com/v1", model: "deepseek-chat")
    }

    static func qwen() -> ModelProvider {
        ModelProvider(
            name: L("通义千问"),
            baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            model: "qwen-plus"
        )
    }
}
