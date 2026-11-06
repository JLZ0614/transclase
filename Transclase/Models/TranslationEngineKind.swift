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
        case .apple: return L("系统离线翻译")
        case .localQwen: return L("本地 Qwen3")
        case .cloud: return L("云端 API")
        }
    }

    var subtitle: String {
        switch self {
        case .apple:
            return L("最快，完全离线，需要下载语言包")
        case .localQwen:
            return L("离线，可注入上下文，需要先在本机跑起模型")
        case .cloud:
            return L("质量最好，需要联网和自己填 API Key")
        }
    }
}


/// Interface language. Applies through AppleLanguages and needs a relaunch.
enum AppLanguage: String, Codable, CaseIterable, Identifiable {
    case system
    case chinese = "zh-Hans"
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case japanese = "ja"
    case korean = "ko"

    var id: String { rawValue }

    /// Native names: a language picker should be readable to the person who
    /// speaks that language, whatever the current UI language is.
    var title: String {
        switch self {
        case .system: return NSLocalizedString("跟随系统", comment: "")
        case .chinese: return L("简体中文")
        case .english: return "English"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        }
    }

    var localeIdentifier: String? {
        self == .system ? nil : rawValue
    }

    /// Applies the choice to the app domain. Takes effect on next launch.
    func apply() {
        let defaults = UserDefaults.standard
        switch self {
        case .system:
            defaults.removeObject(forKey: "AppleLanguages")
        case .chinese:
            defaults.set(["zh-Hans"], forKey: "AppleLanguages")
        case .english:
            defaults.set(["en"], forKey: "AppleLanguages")
        case .spanish:
            defaults.set(["es"], forKey: "AppleLanguages")
        case .french:
            defaults.set(["fr"], forKey: "AppleLanguages")
        case .german:
            defaults.set(["de"], forKey: "AppleLanguages")
        case .japanese:
            defaults.set(["ja"], forKey: "AppleLanguages")
        case .korean:
            defaults.set(["ko"], forKey: "AppleLanguages")
        }
    }
}
