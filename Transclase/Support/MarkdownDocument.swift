import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// `.md` isn't guaranteed to be registered, so fall back to plain text.
    static let markdownText = UTType(filenameExtension: "md") ?? .plainText
}

/// Plain-text document used by the export panel.
struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.markdownText, .plainText] }

    var text: String

    init(text: String) {
        self.text = text
    }

    init(configuration: ReadConfiguration) throws {
        let data = configuration.file.regularFileContents ?? Data()
        text = String(data: data, encoding: .utf8) ?? ""
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
