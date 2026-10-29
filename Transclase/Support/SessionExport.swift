import Foundation

enum SessionExport {
    static func markdown(
        captions: [Caption],
        sourceName: String,
        targetName: String,
        startedAt: Date
    ) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        var lines: [String] = []
        lines.append("# Lecture transcript")
        lines.append("")
        lines.append("- Date: \(formatter.string(from: startedAt))")
        lines.append("- Languages: \(sourceName) → \(targetName)")
        lines.append("- Segments: \(captions.count)")
        lines.append("")
        lines.append("---")
        lines.append("")

        for caption in captions {
            lines.append("**[\(timecode(caption.start))]**")
            lines.append("")
            lines.append("> \(caption.source)")
            if let target = caption.target, !target.isEmpty {
                lines.append("")
                lines.append("\(target)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    static func plainText(captions: [Caption]) -> String {
        captions
            .map { caption in
                if let target = caption.target, !target.isEmpty {
                    return "\(caption.source)\n\(target)"
                }
                return caption.source
            }
            .joined(separator: "\n\n")
    }

    static func timecode(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        let total = Int(seconds.rounded())
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}
