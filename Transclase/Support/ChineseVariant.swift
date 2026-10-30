import Foundation

/// Apple's generic `zh` translation model can occasionally emit Traditional
/// characters — the variant appears to follow the *system* language preference
/// rather than the requested identifier, so a lecture can flip between 简/繁
/// mid-sentence. When the user asked for Simplified we normalise the output so
/// the transcript stays consistent.
enum ChineseVariant {
    static func normalized(_ text: String, for targetLanguageID: String) -> String {
        guard isSimplifiedTarget(targetLanguageID) else { return text }
        // The ICU transform is idempotent on already-Simplified text.
        return text.applyingTransform(StringTransform("Hant-Hans"), reverse: false) ?? text
    }

    static func isSimplifiedTarget(_ id: String) -> Bool {
        switch id {
        case "zh-Hans", "zh-CN", "zh-SG", "zh":
            return true
        default:
            return false
        }
    }
}
