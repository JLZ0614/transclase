import Foundation
import FoundationModels

/// Fallback translator that uses Apple Intelligence's on-device foundation model.
///
/// Apple's `Translation` framework needs a downloaded language pack per pair.
/// When a pack is missing we can still translate on-device by prompting the
/// system model — no download, no network, at the cost of lower quality and
/// higher latency. Requires an Apple Intelligence–capable device with Apple
/// Intelligence enabled.
@MainActor
final class FoundationModelTranslationEngine: MTEngine {
    private let sourceName: String
    private let targetName: String

    init(sourceName: String, targetName: String) {
        self.sourceName = sourceName
        self.targetName = targetName
    }

    static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability {
            return true
        }
        return false
    }

    func prepare() async throws {
        guard Self.isAvailable else { throw MTError.foundationModelUnavailable }
    }

    func translate(_ text: String) async throws -> String {
        var instructions = """
        You are a professional simultaneous interpreter for university lectures. \
        Translate the user's \(sourceName) text into \(targetName). \
        Output only the translation — no quotes, no notes, no explanations. \
        Keep formulas, code, names and abbreviations in their original form.
        """
        do {
            // A fresh session per sentence keeps each translation independent;
            // a long-lived session would drift and accumulate context.
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: text)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw MTError.failed(error.localizedDescription)
        }
    }
}
