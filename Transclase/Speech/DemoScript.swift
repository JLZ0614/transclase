import Foundation

/// Scripted lecture used by demo mode. Demo mode exists because the on-device
/// speech model and the translation language packs both need to be present on
/// the machine; demo mode lets anyone exercise the whole UI and pipeline
/// immediately, including in the Simulator.
enum DemoScript {
    struct Line {
        let english: String
        let chinese: String
    }

    static let lines: [Line] = [
        Line(
            english: "Today we're going to look at how gradient descent actually finds a minimum.",
            chinese: "今天我们要看梯度下降究竟是如何找到最小值的。"
        ),
        Line(
            english: "The key idea is that the gradient points in the direction of steepest ascent.",
            chinese: "关键思想是，梯度指向最陡上升的方向。"
        ),
        Line(
            english: "So if we walk in the opposite direction, we should be going downhill.",
            chinese: "所以如果我们朝相反方向走，就应该是在下坡。"
        ),
        Line(
            english: "The step size, or learning rate, controls how far we move each time.",
            chinese: "步长，也就是学习率，控制我们每次移动多远。"
        ),
        Line(
            english: "If it is too large, the algorithm will overshoot and may even diverge.",
            chinese: "如果它太大，算法会冲过头，甚至可能发散。"
        ),
        Line(
            english: "If it is too small, convergence becomes painfully slow.",
            chinese: "如果它太小，收敛会慢得让人难受。"
        ),
        Line(
            english: "In practice we often decay the learning rate over time.",
            chinese: "在实践中，我们通常会随着时间衰减学习率。"
        ),
        Line(
            english: "Now, what happens when the function is not convex?",
            chinese: "那么，当函数不是凸函数时会发生什么？"
        ),
        Line(
            english: "You can get stuck in a local minimum, or in a saddle point.",
            chinese: "你可能会卡在局部最小值，或者鞍点。"
        ),
        Line(
            english: "That is why initialization matters more than most people expect.",
            chinese: "这就是为什么初始化比大多数人以为的更重要。"
        ),
    ]

    static func translation(for english: String) -> String? {
        let normalized = normalize(english)
        return lines.first { normalize($0.english) == normalized }?.chinese
    }

    private static func normalize(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: "'", with: "")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }
}
