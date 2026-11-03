import Foundation

/// Which translation backend the user picked. All three keep the same
/// transcription pipeline; only the text-to-text step changes.
enum TranslationEngineKind: String, Codable, CaseIterable, Identifiable {
    /// Apple's on-device translation framework. Fastest, needs language packs.
    case apple
    /// Qwen3 running locally (Ollama / LM Studio, OpenAI-compatible endpoint).
    case localQwen
    /// Any OpenAI-compatible cloud endpoint.
    case cloud

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: return "系统离线翻译"
        case .localQwen: return "本地 Qwen3"
        case .cloud: return "云端 API"
        }
    }

    var subtitle: String {
        switch self {
        case .apple:
            return "最快，完全离线，需要下载语言包"
        case .localQwen:
            return "离线，可注入上下文，需要先在本机跑起模型"
        case .cloud:
            return "质量最好，需要联网和自己填 API Key"
        }
    }
}
