import Foundation

/// A course-specific term pair. Lectures are full of jargon that general
/// translation models mangle, so the app lets the user pin a preferred
/// translation per term.
struct GlossaryTerm: Identifiable, Codable, Hashable {
    var id: UUID
    var source: String
    var target: String

    init(id: UUID = UUID(), source: String, target: String) {
        self.id = id
        self.source = source
        self.target = target
    }

    static let samples: [GlossaryTerm] = [
        GlossaryTerm(source: "derivative", target: "导数"),
        GlossaryTerm(source: "gradient descent", target: "梯度下降"),
        GlossaryTerm(source: "eigenvalue", target: "特征值"),
        GlossaryTerm(source: "opportunity cost", target: "机会成本"),
        GlossaryTerm(source: "randomized controlled trial", target: "随机对照试验"),
    ]
}
