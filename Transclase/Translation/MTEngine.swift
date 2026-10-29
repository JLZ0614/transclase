import Foundation
import Translation

enum MTError: LocalizedError {
    case sessionNotReady
    case unsupportedPair(String)
    case notInstalled(String)
    case foundationModelUnavailable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .sessionNotReady:
            return "翻译会话尚未就绪，请稍候再试。"
        case .unsupportedPair(let pair):
            return "这台设备不支持 \(pair) 的离线翻译。"
        case .notInstalled(let pair):
            return "\(pair) 的离线语言包还没下载。请在设置里点“下载语言包”，或在系统“翻译”App 中添加该语言。"
        case .foundationModelUnavailable:
            return "这台设备没有可用的 Apple 智能本地模型。"
        case .failed(let message):
            return "翻译失败：\(message)"
        }
    }
}

@MainActor
protocol MTEngine: AnyObject {
    func prepare() async throws
    func translate(_ text: String) async throws -> String
}
