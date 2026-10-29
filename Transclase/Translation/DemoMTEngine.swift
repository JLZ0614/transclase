import Foundation

/// Canned translations so the app is fully usable without any language packs.
@MainActor
final class DemoMTEngine: MTEngine {
    func prepare() async throws {}

    func translate(_ text: String) async throws -> String {
        try? await Task.sleep(nanoseconds: 140_000_000)
        if let translation = DemoScript.translation(for: text) {
            return translation
        }
        return "（演示翻译）\(text)"
    }
}

/// Post-edit pass that enforces the user's course glossary.
///
/// This cannot fix a wrong translation without knowing what the model produced,
/// but it reliably catches the most common and most visible failure: a term the
/// model left in the source language (acronyms, product names, novel jargon).
struct GlossaryProcessor {
    let terms: [GlossaryTerm]

    func apply(to translation: String, sourceText: String) -> String {
        var result = translation
        for term in terms {
            let source = term.source.trimmingCharacters(in: .whitespaces)
            let target = term.target.trimmingCharacters(in: .whitespaces)
            guard !source.isEmpty, !target.isEmpty else { continue }

            let appearsInSource = sourceText.range(
                of: source,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
            guard appearsInSource else { continue }

            // If the target term is already there, leave it alone.
            if result.range(of: target, options: [.caseInsensitive]) != nil { continue }

            // Otherwise the model probably echoed the source term: replace it.
            if result.range(of: source, options: [.caseInsensitive]) != nil {
                result = result.replacingOccurrences(
                    of: source,
                    with: target,
                    options: [.caseInsensitive]
                )
            }
        }
        return result
    }
}
