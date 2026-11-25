import Foundation

/// Translates through any OpenAI-compatible `/chat/completions` endpoint — a
/// local Ollama on 127.0.0.1, or a cloud provider. Both paths share this code;
/// only the base URL and credential differ.
final class OpenAICompatibleEngine: MTEngine {
    private let baseURL: URL
    private let model: String
    private let apiKey: String?
    private let sourceName: String
    private let targetName: String
    private let session: URLSession

    /// Last couple of sentence pairs, so pronouns and omitted subjects survive.
    /// Guarded because several sentences may be in flight at once.
    private var history: [(source: String, target: String)] = []
    private let historyLock = NSLock()

    init(baseURL: URL, model: String, apiKey: String?, sourceName: String, targetName: String) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.sourceName = sourceName
        self.targetName = targetName

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    // MARK: - MTEngine

    func prepare() async throws {
        if baseURL.isFileURL { throw MTError.failed(L("端点地址无效")) }
        // A cheap reachability probe: better to fall back once at start than to
        // fail on every single sentence.
        _ = try? await request(path: "models", method: "GET", body: nil, timeout: 6)
        guard await reachable() else {
            throw MTError.failed("连不上 \(baseURL.absoluteString)，请确认服务已启动")
        }
    }

    func translate(_ text: String) async throws -> String {
        let body: [String: Any] = [
            "model": model,
            "temperature": 0.1,
            "stream": false,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": userPrompt(for: text)],
            ],
        ]

        let payload = try JSONSerialization.data(withJSONObject: body)
        let data = try await withRetry {
            try await self.request(
                path: "chat/completions",
                method: "POST",
                body: payload,
                timeout: 20
            )
        }

        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else {
            throw MTError.failed(L("返回格式无法解析"))
        }

        let cleaned = Self.clean(content)
        guard !cleaned.isEmpty else { throw MTError.failed(L("模型返回空结果")) }

        recordHistory(text, cleaned)
        return cleaned
    }

    // MARK: - History

    /// Locking lives in a synchronous helper: calling `NSLock.lock()` directly
    /// after an `await` is a Swift 6 error.
    private func recordHistory(_ source: String, _ target: String) {
        historyLock.lock()
        defer { historyLock.unlock() }
        history.append((source, target))
        if history.count > 2 { history.removeFirst(history.count - 2) }
    }

    private func historySnapshot() -> [(source: String, target: String)] {
        historyLock.lock()
        defer { historyLock.unlock() }
        return history
    }

    // MARK: - Prompts

    private var systemPrompt: String {
        """
        You are a professional interpreter for university lectures. \
        Translate the user's \(sourceName) text into \(targetName). \
        Output ONLY the translation: no quotes, no notes, no explanations, \
        no romanisation. Keep formulas, code, names and abbreviations as-is. \
        If a sentence is incomplete, translate what is there without inventing \
        the rest.
        """
    }

    private func userPrompt(for text: String) -> String {
        let snapshot = historySnapshot()
        guard !snapshot.isEmpty else { return text }
        let context = snapshot
            .map { "\($0.source)\n→ \($0.target)" }
            .joined(separator: "\n\n")
        return """
        Previous sentences (for context only, do not repeat them):
        \(context)

        Translate only this sentence:
        \(text)
        """
    }

    /// Cloud endpoints occasionally answer 429/503 or drop the connection for a
    /// single sentence. Retrying turns those into a short delay instead of a
    /// permanently untranslated caption.
    private func withRetry(_ operation: () async throws -> Data) async throws -> Data {
        var lastError: Error?
        for attempt in 0..<3 {
            do {
                return try await operation()
            } catch {
                lastError = error
                guard Self.isTransient(error) else { throw error }
                let pause = 0.5 * Double(attempt + 1)
                try? await Task.sleep(nanoseconds: UInt64(pause * 1_000_000_000))
            }
        }
        throw lastError ?? MTError.failed(L("翻译请求失败"))
    }

    private static func isTransient(_ error: Error) -> Bool {
        guard case let MTError.failed(message) = error else { return true }
        if message.contains("HTTP 429") || message.contains("HTTP 5") { return true }
        // URLSession timeouts and dropped connections arrive as plain errors.
        return message.contains("The request timed out")
            || message.contains("网络连接已中断")
            || message.contains("network connection was lost")
            || message.contains("超时")
    }

    // MARK: - Transport

    private func reachable() async -> Bool {
        let data = try? await request(path: "models", method: "GET", body: nil, timeout: 6)
        return data != nil
    }

    private func request(
        path: String,
        method: String,
        body: Data?,
        timeout: TimeInterval
    ) async throws -> Data {
        var url = baseURL
        if !url.path.hasSuffix("/") { url.appendPathComponent("") }
        url.appendPathComponent(path)

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MTError.failed(L("没有收到 HTTP 响应"))
        }
        guard (200..<300).contains(http.statusCode) else {
            let snippet = String(data: data.prefix(200), encoding: .utf8) ?? ""
            throw MTError.failed("HTTP \(http.statusCode) \(snippet)")
        }
        return data
    }

    // MARK: - Output hygiene

    /// Qwen3 can emit a reasoning block before the answer, and some models
    /// cheerfully prepend L("以下是翻译：").
    static func clean(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        while let start = text.range(of: " thinking"), let end = text.range(of: "<｜end▁of▁thinking｜>") {
            text.removeSubrange(start.lowerBound..<end.upperBound)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        for prefix in [L("以下是翻译："), L("以下是翻译:"), L("翻译："), L("译文："), "Translation:"] {
            if text.hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") {
            text = String(text.dropFirst().dropLast())
        }
        if text.count >= 2, text.hasPrefix("“"), text.hasSuffix("”") {
            text = String(text.dropFirst().dropLast())
        }
        return text
    }
}
