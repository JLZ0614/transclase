import Foundation
import Translation

enum MTError: LocalizedError {
    case sessionNotReady
    case unsupportedPair(String)
    case notInstalled(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .sessionNotReady:
            return L("翻译会话尚未就绪，请稍候再试。")
        case .unsupportedPair(let pair):
            return "这台设备不支持 \(pair) 的离线翻译。"
        case .notInstalled(let pair):
            return "\(pair) 的离线语言包还没下载。请在设置里点“下载语言包”，或在系统“翻译”App 中添加该语言。"
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
