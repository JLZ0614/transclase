import Foundation

struct SummaryBlock: Identifiable, Equatable {
    let id = UUID()
    var createdAt: Date
    var range: String
    var markdown: String
}

struct AssistantTurn: Identifiable, Equatable {
    let id = UUID()
    var isUser: Bool
    var text: String
}
