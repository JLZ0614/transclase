import Foundation
import Speech
import Translation

struct LanguageOption: Identifiable, Hashable {
    let id: String
    let displayName: String
    let isInstalled: Bool
}

enum LanguageMapping {
    /// Locale used by the speech transcriber.
    static func speechLocale(_ id: String) -> Locale {
        Locale(identifier: id)
    }

    /// `SpeechTranscriber` speaks BCP-47 with regions; the translation
    /// framework speaks coarse language codes. Chinese keeps the script
    /// distinction because `zh` and `zh-TW` are separate model packs.
    static func translationLanguage(_ id: String) -> Locale.Language {
        switch id {
        case "zh-Hans", "zh-CN", "zh-SG":
            return Locale.Language(identifier: "zh")
        case "zh-Hant", "zh-TW", "zh-HK":
            return Locale.Language(identifier: "zh-TW")
        default:
            let base = id.split(separator: "-").first.map(String.init) ?? id
            return Locale.Language(identifier: base)
        }
    }

    /// Inverse of `translationLanguage`, for persisting a picker selection.
    static func settingsID(for language: Locale.Language) -> String {
        switch language.minimalIdentifier {
        case "zh": return "zh-Hans"
        case "zh-TW": return "zh-Hant"
        default: return language.minimalIdentifier
        }
    }

    static func displayName(forBCP47 id: String) -> String {
        Locale.current.localizedString(forIdentifier: id)
            ?? Locale(identifier: "zh-Hans").localizedString(forIdentifier: id)
            ?? id
    }

    /// Target name used inside model prompts. Generic names like "Chinese"
    /// invite the model to pick either variant.
    static func promptName(for id: String) -> String {
        switch id {
        case "zh-Hans", "zh-CN", "zh-SG", "zh":
            return "Simplified Chinese (简体中文)"
        case "zh-Hant", "zh-TW", "zh-HK":
            return "Traditional Chinese (繁體中文)"
        default:
            return displayName(forBCP47: id)
        }
    }

    static func displayName(forLanguage language: Locale.Language) -> String {
        Locale.current.localizedString(forLanguageCode: language.minimalIdentifier)
            ?? Locale(identifier: "zh-Hans").localizedString(forLanguageCode: language.minimalIdentifier)
            ?? language.minimalIdentifier
    }
}

/// Runtime capability discovery. Nothing is hard-coded: what a device can
/// recognise and translate depends on the OS version and on which model packs
/// the user has downloaded, so we ask the frameworks.
struct LanguageCatalog {
    let speech: [LanguageOption]
    let translation: [LanguageOption]

    static func load() async -> LanguageCatalog {
        async let speech = loadSpeech()
        async let translation = loadTranslation()
        return LanguageCatalog(speech: await speech, translation: await translation)
    }

    private static func loadSpeech() async -> [LanguageOption] {
        // These framework calls can be slow (or hang on a fresh simulator), and
        // nothing in the app should block on them.
        let supported: [String] = await withTimeout(seconds: 3) { () async -> [String] in
            await SpeechTranscriber.supportedLocales.map { $0.identifier(.bcp47) }
        } ?? []
        let installedIDs: [String] = await withTimeout(seconds: 3) { () async -> [String] in
            await SpeechTranscriber.installedLocales.map { $0.identifier(.bcp47) }
        } ?? []
        let installed = Set(installedIDs)
        return supported
            .map {
                LanguageOption(
                    id: $0,
                    displayName: LanguageMapping.displayName(forBCP47: $0),
                    isInstalled: installed.contains($0)
                )
            }
            .sorted { $0.displayName < $1.displayName }
    }

    private static func loadTranslation() async -> [LanguageOption] {
        let languages: [Locale.Language] = await withTimeout(seconds: 3) { () async -> [Locale.Language] in
            await LanguageAvailability().supportedLanguages
        } ?? []
        return languages
            .map {
                LanguageOption(
                    id: LanguageMapping.settingsID(for: $0),
                    displayName: LanguageMapping.displayName(forLanguage: $0),
                    isInstalled: false
                )
            }
            .sorted { $0.displayName < $1.displayName }
    }
}

/// Runs `operation`, giving up after `seconds`. Used so a stalled framework
/// call degrades the UI instead of freezing it.
func withTimeout<T: Sendable>(
    seconds: Double,
    _ operation: @escaping @Sendable () async -> T
) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}
