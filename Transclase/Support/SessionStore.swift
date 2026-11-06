import Foundation

/// One markdown document per lecture. The file name is the session title
/// (weekday + date), the body starts as the bilingual transcript and gets
/// summary sections appended as they are generated.
struct LectureSession: Identifiable, Hashable {
    let id: String          // file name without extension, e.g. L("周三-11-05")
    let url: URL
    let createdAt: Date

    var displayName: String { id.replacingOccurrences(of: "-", with: " ") }
}

enum SessionStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
        return base.appendingPathComponent("Transclase/Sessions", isDirectory: true)
    }

    private static var formatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hans_CN")
        f.dateFormat = "EEE-MM-dd"
        return f
    }

    static func fileName(for date: Date = Date()) -> String {
        formatter.string(from: date).replacingOccurrences(of: " ", with: "-")
    }

    static func create(at date: Date = Date()) -> LectureSession {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var name = fileName(for: date)
        var url = directory.appendingPathComponent("\(name).md")
        var suffix = 2
        while FileManager.default.fileExists(atPath: url.path) {
            name = "\(fileName(for: date))-\(suffix)"
            url = directory.appendingPathComponent("\(name).md")
            suffix += 1
        }
        let header = """
        # \(formatter.string(from: date))

        > 由 Transclase 自动生成 · \(DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short))

        """
        try? header.write(to: url, atomically: true, encoding: .utf8)
        return LectureSession(id: name, url: url, createdAt: date)
    }

    static func list() -> [LectureSession] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.creationDateKey]) else {
            return []
        }
        return files
            .filter { $0.pathExtension == "md" }
            .compactMap { url in
                let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return LectureSession(
                    id: url.deletingPathExtension().lastPathComponent,
                    url: url,
                    createdAt: created
                )
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func append(_ text: String, to session: LectureSession) {
        guard let handle = try? FileHandle(forWritingTo: session.url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        if let data = text.data(using: .utf8) {
            try? handle.write(contentsOf: data)
        }
    }

    /// Parses a session document back into captions and summary blocks so a
    /// past lecture can be reopened and continued.
    static func load(_ session: LectureSession) -> (captions: [Caption], summaries: [SummaryBlock]) {
        let text = read(session)
        var captions: [Caption] = []
        var summaries: [SummaryBlock] = []

        let captionPattern = try? NSRegularExpression(
            pattern: #"\*\*\[(\d{2}:\d{2})\]\*\*\s*\n\s*>\s*([\s\S]*?)\n\s*\n([\s\S]*?)(?=\n\*\*\[|\n## |\z)"#
        )
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        captionPattern?.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let match else { return }
            let time = ns.substring(with: match.range(at: 1))
            let source = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            let target = ns.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = time.split(separator: ":").compactMap { Double($0) }
            let start = parts.count == 2 ? parts[0] * 60 + parts[1] : 0
            captions.append(
                Caption(
                    id: "\(session.id)-\(captions.count)",
                    source: source,
                    target: target.isEmpty ? nil : target,
                    isFinal: true,
                    state: target.isEmpty ? .idle : .done,
                    start: start,
                    end: start
                )
            )
        }

        let summaryPattern = try? NSRegularExpression(
            pattern: #"## 要点 ([0-9:–\-]+)\n([\s\S]*?)(?=\n## |\z)"#
        )
        summaryPattern?.enumerateMatches(in: text, range: full) { match, _, _ in
            guard let match else { return }
            let range = ns.substring(with: match.range(at: 1))
            let body = ns.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return }
            summaries.append(SummaryBlock(createdAt: Date(), range: range, markdown: body))
        }

        return (captions, summaries)
    }

    static func read(_ session: LectureSession) -> String {
        (try? String(contentsOf: session.url, encoding: .utf8)) ?? ""
    }
}
