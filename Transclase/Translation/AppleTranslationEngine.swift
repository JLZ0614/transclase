import Foundation
import Translation

/// On-device translation through Apple's `Translation` framework.
///
/// The session is *not* created here. Apple only exposes download-capable
/// sessions through SwiftUI's `.translationTask` modifier, which is what shows
/// the system language-pack prompt. `AppModel` installs that session before the
/// pipeline starts translating.
@MainActor
final class AppleTranslationEngine: MTEngine {
    private let source: Locale.Language
    private let target: Locale.Language
    private let sessionProvider: () -> TranslationSession?

    init(
        source: Locale.Language,
        target: Locale.Language,
        sessionProvider: @escaping () -> TranslationSession?
    ) {
        self.source = source
        self.target = target
        self.sessionProvider = sessionProvider
    }

    func prepare() async throws {
        let availability = LanguageAvailability()
        let status = await availability.status(from: source, to: target)
        switch status {
        case .unsupported:
            throw MTError.unsupportedPair(pairName)
        case .installed:
            return
        case .supported:
            // Installable but not downloaded: the session from `.translationTask`
            // will own the download prompt.
            return
        @unknown default:
            return
        }
    }

    func translate(_ text: String) async throws -> String {
        guard let session = sessionProvider() else {
            throw MTError.sessionNotReady
        }
        do {
            let response = try await session.translate(text)
            return response.targetText
        } catch let error as TranslationError {
            if TranslationError.notInstalled ~= error {
                throw MTError.notInstalled(pairName)
            }
            if TranslationError.unsupportedLanguagePairing ~= error {
                throw MTError.unsupportedPair(pairName)
            }
            throw MTError.failed(error.localizedDescription)
        } catch {
            throw MTError.failed(error.localizedDescription)
        }
    }

    private var pairName: String {
        "\(LanguageMapping.displayName(forLanguage: source)) → \(LanguageMapping.displayName(forLanguage: target))"
    }
}
