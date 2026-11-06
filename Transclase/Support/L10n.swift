import Foundation

/// Explicit lookup instead of relying on `Bundle.main`'s lazily-cached
/// localisation: `Text("…")` resolves through SwiftUI's own cache and does not
/// follow a runtime language change, so views call `L("…")` instead.
enum L10n {
    /// Current interface language, `nil` = follow the system.
    nonisolated(unsafe) static var language: String?

    private static var cache: [String: String] = [:]
    private static let lock = NSLock()

    static func set(_ language: String?) {
        lock.lock()
        cache.removeAll()
        lock.unlock()
        Self.language = language
    }

    static func string(_ key: String) -> String {
        let active = language ?? systemLanguage
        guard let active, active != "zh-Hans", active != "zh-Hant" else { return key }

        lock.lock()
        if let hit = cache[key] {
            lock.unlock()
            return hit
        }
        lock.unlock()

        guard let path = Bundle.main.path(forResource: active, ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        let value = bundle.localizedString(forKey: key, value: nil, table: nil)
        // `localizedString(forKey:)` returns the key itself when missing.
        let resolved = value == key ? englishFallback(key, active: active) : value

        lock.lock()
        cache[key] = resolved
        lock.unlock()
        return resolved
    }

    /// A language table should be complete; if it is not, fall back to English
    /// rather than leaking Chinese into a non-Chinese interface.
    private static func englishFallback(_ key: String, active: String) -> String {
        guard active != "en",
              let path = Bundle.main.path(forResource: "en", ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        let value = bundle.localizedString(forKey: key, value: nil, table: nil)
        return value == key ? key : value
    }

    private static var systemLanguage: String? {
        guard let preferred = Locale.preferredLanguages.first else { return nil }
        if preferred.hasPrefix("zh") { return "zh-Hans" }
        return String(preferred.prefix(2))
    }

    /// Locale used for language names, so "English (US)" is shown in the
    /// selected interface language.
    static var locale: Locale {
        guard let language, language != "zh-Hans",
              let identifier = Locale.availableIdentifiers.first(where: {
                  Locale(identifier: $0).language.languageCode?.identifier == language
              })
        else { return Locale.current }
        return Locale(identifier: identifier)
    }
}

/// Shorthand: `Text(L("新对话"))`.
func L(_ key: String) -> String { L10n.string(key) }
