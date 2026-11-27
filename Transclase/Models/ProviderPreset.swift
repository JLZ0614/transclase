import Foundation

/// One OpenAI-compatible provider preset: address, default models and the page
/// where the user creates an API key. Picking a preset means the only field the
/// user fills in is the key.
struct ProviderPreset: Identifiable, Hashable {
    let id: String
    let name: String
    let baseURL: String
    let models: [String]
    let apiKeyURL: String

    static let all: [ProviderPreset] = [
        ProviderPreset(
            id: "deepseek", name: "DeepSeek",
            baseURL: "https://api.deepseek.com/v1",
            models: ["deepseek-chat", "deepseek-reasoner"],
            apiKeyURL: "https://platform.deepseek.com/api_keys"
        ),
        ProviderPreset(
            id: "openai", name: "OpenAI",
            baseURL: "https://api.openai.com/v1",
            models: ["gpt-4o-mini", "gpt-4o", "gpt-4.1-mini"],
            apiKeyURL: "https://platform.openai.com/api-keys"
        ),
        ProviderPreset(
            id: "moonshot", name: "Moonshot 月之暗面",
            baseURL: "https://api.moonshot.cn/v1",
            models: ["moonshot-v1-8k", "moonshot-v1-32k", "kimi-k2-0905-preview"],
            apiKeyURL: "https://platform.moonshot.cn/console/api-keys"
        ),
        ProviderPreset(
            id: "zhipu", name: "智谱 GLM",
            baseURL: "https://open.bigmodel.cn/api/paas/v4",
            models: ["glm-4-flash", "glm-4-plus", "glm-4.5"],
            apiKeyURL: "https://bigmodel.cn/usercenter/apikeys"
        ),
        ProviderPreset(
            id: "dashscope", name: "通义千问",
            baseURL: "https://dashscope.aliyuncs.com/compatible-mode/v1",
            models: ["qwen-plus", "qwen-turbo", "qwen-max"],
            apiKeyURL: "https://bailian.console.aliyun.com/?apiKey=1"
        ),
        ProviderPreset(
            id: "siliconflow", name: "硅基流动",
            baseURL: "https://api.siliconflow.cn/v1",
            models: ["deepseek-ai/DeepSeek-V3", "Qwen/Qwen2.5-7B-Instruct"],
            apiKeyURL: "https://cloud.siliconflow.cn/account/ak"
        ),
        ProviderPreset(
            id: "openrouter", name: "OpenRouter",
            baseURL: "https://openrouter.ai/api/v1",
            models: ["openai/gpt-4o-mini", "anthropic/claude-3.5-sonnet", "deepseek/deepseek-chat"],
            apiKeyURL: "https://openrouter.ai/keys"
        ),
        ProviderPreset(
            id: "groq", name: "Groq",
            baseURL: "https://api.groq.com/openai/v1",
            models: ["llama-3.3-70b-versatile", "mixtral-8x7b-32768"],
            apiKeyURL: "https://console.groq.com/keys"
        ),
        ProviderPreset(
            id: "xai", name: "xAI Grok",
            baseURL: "https://api.x.ai/v1",
            models: ["grok-2-latest", "grok-beta"],
            apiKeyURL: "https://console.x.ai/"
        ),
        ProviderPreset(
            id: "mistral", name: "Mistral",
            baseURL: "https://api.mistral.ai/v1",
            models: ["mistral-small-latest", "mistral-large-latest"],
            apiKeyURL: "https://console.mistral.ai/api-keys"
        ),
        ProviderPreset(
            id: "minimax", name: "MiniMax",
            baseURL: "https://api.minimax.chat/v1",
            models: ["abab6.5s-chat"],
            apiKeyURL: "https://platform.minimaxi.com/user-center/basic-information/interface-key"
        ),
        ProviderPreset(
            id: "ollama", name: "本地 Ollama",
            baseURL: "http://127.0.0.1:11434/v1",
            models: ["qwen2.5:7b", "llama3.2"],
            apiKeyURL: "https://ollama.com/download"
        ),
    ]
}
