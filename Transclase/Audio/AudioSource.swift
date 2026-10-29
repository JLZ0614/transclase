import AVFoundation
import Foundation

enum AudioError: LocalizedError {
    case permissionDenied
    case noInputDevice
    case engineFailed(String)
    case conversionUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "没有麦克风权限。请到系统设置中允许 Transclase 使用麦克风。"
        case .noInputDevice:
            return "找不到可用的麦克风。请检查音频输入设备。"
        case .engineFailed(let message):
            return "音频引擎启动失败：\(message)"
        case .conversionUnavailable:
            return "无法在麦克风格式和识别模型格式之间转换。"
        }
    }
}

/// Anything that can hand us a stream of PCM buffers (microphone today,
/// system audio tap later).
protocol AudioSource: AnyObject {
    var format: AVAudioFormat { get }
    func start() async throws -> AsyncStream<AVAudioPCMBuffer>
    func stop()
}

/// Microphone capture that behaves the same on macOS, iPadOS and iOS.
final class MicrophoneSource: AudioSource {
    private let engine = AVAudioEngine()
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var tapInstalled = false
    var onLevel: (@Sendable (Float) -> Void)?

    var format: AVAudioFormat {
        engine.inputNode.outputFormat(forBus: 0)
    }

    func start() async throws -> AsyncStream<AVAudioPCMBuffer> {
        try await Self.requestPermission()

        #if os(iOS)
        try configureAudioSession()
        #endif

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw AudioError.noInputDevice
        }

        let (stream, continuation) = AsyncStream<AVAudioPCMBuffer>.makeStream(
            bufferingPolicy: .bufferingNewest(64)
        )
        self.continuation = continuation

        let levelHandler = onLevel
        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { buffer, _ in
            levelHandler?(Self.rms(of: buffer))
            if let copy = Self.copy(buffer) {
                continuation.yield(copy)
            }
        }
        tapInstalled = true

        engine.prepare()
        do {
            try engine.start()
        } catch {
            if tapInstalled {
                input.removeTap(onBus: 0)
                tapInstalled = false
            }
            self.continuation = nil
            throw AudioError.engineFailed(error.localizedDescription)
        }

        return stream
    }

    func stop() {
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning {
            engine.stop()
        }
        continuation?.finish()
        continuation = nil

        #if os(iOS)
        // Leaving the session active keeps the system microphone indicator lit.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    // MARK: - Platform setup

    private static func requestPermission() async throws {
        let granted: Bool = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
        if !granted { throw AudioError.permissionDenied }
    }

    #if os(iOS)
    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        // `.measurement` disables the aggressive processing that makes far-field
        // lecture audio sound "clean" to a human but destroys it for an ASR model.
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true, options: [])
    }
    #endif

    // MARK: - Buffer helpers

    /// The tap reuses its buffer memory, so anything handed to another task
    /// must be a deep copy.
    static func copy(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard
            let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength)
        else { return nil }
        copy.frameLength = buffer.frameLength

        let channels = Int(buffer.format.channelCount)
        let frames = Int(buffer.frameLength)
        if let source = buffer.floatChannelData, let destination = copy.floatChannelData {
            for channel in 0..<channels {
                memcpy(destination[channel], source[channel], frames * MemoryLayout<Float>.size)
            }
            return copy
        }
        if let source = buffer.int16ChannelData, let destination = copy.int16ChannelData {
            for channel in 0..<channels {
                memcpy(destination[channel], source[channel], frames * MemoryLayout<Int16>.size)
            }
            return copy
        }
        return nil
    }

    static func rms(of buffer: AVAudioPCMBuffer) -> Float {
        guard
            let data = buffer.floatChannelData,
            buffer.frameLength > 0
        else { return 0 }
        let frames = Int(buffer.frameLength)
        var sum: Float = 0
        let channel = data[0]
        for index in 0..<frames {
            let sample = channel[index]
            sum += sample * sample
        }
        let mean = sum / Float(frames)
        // Map -50 dB…0 dB onto 0…1 so the meter is usable at lecture volume.
        let db = 10 * log10(max(mean, 1e-7))
        return min(max((db + 50) / 50, 0), 1)
    }
}

/// Converts microphone buffers into whatever format the transcription model
/// asked for. Created once per session because `AVAudioConverter` is stateful.
final class BufferConverter {
    private let converter: AVAudioConverter
    private let outputFormat: AVAudioFormat

    init?(from input: AVAudioFormat, to output: AVAudioFormat) {
        guard input != output, let converter = AVAudioConverter(from: input, to: output) else {
            return nil
        }
        self.converter = converter
        self.outputFormat = output
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 128
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return nil
        }

        var provided = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, outStatus in
            if provided {
                outStatus.pointee = .noDataNow
                return nil
            }
            provided = true
            outStatus.pointee = .haveData
            return buffer
        }

        if status == .error || error != nil { return nil }
        return output.frameLength > 0 ? output : nil
    }
}
