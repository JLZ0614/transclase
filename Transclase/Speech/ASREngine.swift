import AVFoundation
import Foundation

enum ASREvent {
    case partial(id: String, text: String, start: TimeInterval, end: TimeInterval)
    case final(id: String, text: String, start: TimeInterval, end: TimeInterval)
    case status(String)
    case failed(String)
}

enum ASRError: LocalizedError {
    case unavailable
    case unsupportedLocale(String)
    case modelDownloadFailed(String)
    case engineFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "此设备不支持系统语音识别模型。"
        case .unsupportedLocale(let locale):
            return "系统语音识别不支持 \(locale)。请换一个语言，或升级系统。"
        case .modelDownloadFailed(let message):
            return "识别模型下载失败：\(message)"
        case .engineFailed(let message):
            return "识别引擎错误：\(message)"
        }
    }
}

/// A transcription backend. Implementations must be usable from a background
/// audio thread for `append`, and publish results through `events`.
protocol ASREngine: AnyObject {
    var events: AsyncStream<ASREvent> { get }
    /// Format the analyzer wants. `nil` means "accept the microphone format".
    var requiredFormat: AVAudioFormat? { get }

    func prepare(locale: Locale) async throws
    func start() async throws
    func append(_ buffer: AVAudioPCMBuffer)
    func stop() async
}
