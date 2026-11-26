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

/// A directory inside the workspace; may contain further folders and lectures.
struct WorkspaceFolder: Identifiable, Hashable {
    let id: String
    let url: URL
    let createdAt: Date
}

enum SessionStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory())
        return base.appendingPathComponent("Transclase/Sessions", isDirectory: true)
    }

    private static var formatter: DateFormatter {
        let f = DateFormatter()
        f.locale = L10n.locale
        f.dateFormat = "EEE-MM-dd-HHmm"
        return f
    }

    static func fileName(for date: Date = Date()) -> String {
        formatter.string(from: date).replacingOccurrences(of: " ", with: "-")
    }

    static func create(at date: Date = Date(), in folder: URL? = nil) -> LectureSession {
        let directory = folder ?? self.directory
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

    /// Source-only transcript of an existing file: quoted lines carry the
    /// recognised text, everything else is translation or metadata.
    static func sourceText(of session: LectureSession) -> String {
        let raw = (try? String(contentsOf: session.url, encoding: .utf8)) ?? ""
        return raw
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { $0.hasPrefix("> ") }
            .map { String($0.dropFirst(2)) }
            .joined(separator: "\n")
    }

    /// Folders and files inside one directory, folders first.
    static func contents(of folder: URL) -> (folders: [WorkspaceFolder], files: [LectureSession]) {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .creationDateKey]
        let items = (try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []

        var folders: [WorkspaceFolder] = []
        var files: [LectureSession] = []
        for url in items {
            let values = try? url.resourceValues(forKeys: Set(keys))
            if values?.isDirectory == true {
                folders.append(WorkspaceFolder(
                    id: url.lastPathComponent,
                    url: url,
                    createdAt: values?.creationDate ?? Date()
                ))
            } else if url.pathExtension == "md" || url.pathExtension == "txt" {
                files.append(LectureSession(
                    id: url.deletingPathExtension().lastPathComponent,
                    url: url,
                    createdAt: values?.creationDate ?? Date()
                ))
            }
        }
        folders.sort { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
        files.sort { $0.createdAt > $1.createdAt }
        return (folders, files)
    }

    @discardableResult
    static func createFolder(named name: String, in parent: URL) -> URL? {
        let fm = FileManager.default
        try? fm.createDirectory(at: parent, withIntermediateDirectories: true)
        var candidate = parent.appendingPathComponent(name, isDirectory: true)
        var suffix = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(name) \(suffix)", isDirectory: true)
            suffix += 1
        }
        do {
            try fm.createDirectory(at: candidate, withIntermediateDirectories: true)
            return candidate
        } catch {
            return nil
        }
    }

    /// Renames a file or folder, keeping the extension for files.
    @discardableResult
    static func rename(_ url: URL, to newName: String) -> URL? {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        let target = url.deletingLastPathComponent()
            .appendingPathComponent(isDirectory ? trimmed : "\(trimmed).\(url.pathExtension)")
        guard target.path != url.path else { return url }
        do {
            try FileManager.default.moveItem(at: url, to: target)
            return target
        } catch {
            return nil
        }
    }

    static func delete(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Every folder under `root`, depth-first — used by the "move to" menu.
    static func allFolders(in root: URL) -> [URL] {
        let fm = FileManager.default
        var result: [URL] = []
        func walk(_ url: URL) {
            let items = (try? fm.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for item in items {
                let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                guard isDir else { continue }
                result.append(item)
                walk(item)
            }
        }
        walk(root)
        return result
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
