import Foundation

/// Thin OpenAI-compatible client shared by the translation engine and the
/// assistant. Keeps transport, auth and error mapping in one place.
struct LLMClient {
    let baseURL: URL
    let model: String
    let apiKey: String?

    enum ClientError: LocalizedError {
        case badStatus(Int, String)
        case malformed
        case empty

        var errorDescription: String? {
            switch self {
            case .badStatus(let code, let body): return "HTTP \(code) \(body.prefix(120))"
            case .malformed: return L("返回格式无法解析")
            case .empty: return L("模型返回空结果")
            }
        }
    }

    /// Fetches the provider's model catalogue so the UI can offer a dropdown.
    func listModels(timeout: TimeInterval = 15) async throws -> [String] {
        var url = baseURL
        if !url.path.hasSuffix("/") { url.appendPathComponent("") }
        url.appendPathComponent("models")

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        let (data, response) = try await URLSession(configuration: config).data(for: request)

        guard let http = response as? HTTPURLResponse else { throw ClientError.malformed }
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.badStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let items = json["data"] as? [[String: Any]]
        else { throw ClientError.malformed }

        let ids = items.compactMap { $0["id"] as? String }.filter { !$0.isEmpty }
        guard !ids.isEmpty else { throw ClientError.empty }
        return ids.sorted()
    }

    func complete(messages: [[String: String]], temperature: Double = 0.2, timeout: TimeInterval = 60) async throws -> String {
        var url = baseURL
        if !url.path.hasSuffix("/") { url.appendPathComponent("") }
        url.appendPathComponent("chat/completions")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "temperature": temperature,
            "stream": false,
            "messages": messages,
        ])

        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout + 15
        let (data, response) = try await URLSession(configuration: config).data(for: request)

        guard let http = response as? HTTPURLResponse else { throw ClientError.malformed }
        guard (200..<300).contains(http.statusCode) else {
            throw ClientError.badStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else { throw ClientError.malformed }

        let cleaned = Self.stripReasoning(content)
        guard !cleaned.isEmpty else { throw ClientError.empty }
        return cleaned
    }

    static func stripReasoning(_ raw: String) -> String {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let start = text.range(of: " thinking"),
              let end = text.range(of: "｜end▁of▁thinking｜") ?? text.range(of: "<｜end▁of▁thinking｜>") {
            text.removeSubrange(start.lowerBound..<end.upperBound)
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }
}
