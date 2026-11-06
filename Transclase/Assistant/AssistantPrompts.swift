import Foundation

/// Prompt builders for the assistant. Kept separate so the wording can be tuned
/// without touching view or transport code.
enum AssistantPrompts {
    static func summary(transcript: String, targetLanguage: String) -> [[String: String]] {
        [
            [
                "role": "system",
                "content": """
                You are a teaching assistant taking notes for a student during a lecture.
                Summarise ONLY what the transcript says. Do not add outside knowledge.
                Write the summary in \(targetLanguage).
                Output 3-5 short bullet points, each starting with "- ".
                Put the single most important takeaway in bold at the top.
                No preamble, no conclusion paragraph.
                """,
            ],
            ["role": "user", "content": "Transcript:\n\n\(transcript)"],
        ]
    }

    static func answer(question: String, transcript: String, targetLanguage: String) -> [[String: String]] {
        [
            [
                "role": "system",
                "content": """
                You are a teaching assistant. Answer the student's question using ONLY
                the lecture transcript below. If the transcript does not contain the
                answer, say so plainly — do not guess.
                Answer in \(targetLanguage), in at most 4 sentences.
                """,
            ],
            [
                "role": "user",
                "content": "Transcript:\n\n\(transcript)\n\nQuestion: \(question)",
            ],
        ]
    }
}
