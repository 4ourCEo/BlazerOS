import Foundation
import BlazerCore

// MARK: - Advisory LLM auditor (async, non-blocking)
//
// Fire-and-forget. A dropped call, timeout, rate limit, or malformed reply must never affect
// scanning, the 8s freshness beam, or local tracking. The caller gets words back; all numbers
// shown to the trader come from `StrikeMath`. The transport is injectable so this is testable
// without a live API.

/// Transport abstraction. The default hits the network; tests inject a stub.
public protocol LLMTransport: Sendable {
    func post(url: URL, headers: [String: String], body: Data) async throws -> Data
}

/// Default transport: JSON POST, hard timeout, 2xx required.
public struct URLSessionTransport: LLMTransport {
    public let timeout: TimeInterval

    public init(timeout: TimeInterval = 6) {
        self.timeout = timeout
    }

    public func post(url: URL, headers: [String: String], body: Data) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw LLMAuditorError.badResponse
        }
        return data
    }
}

public enum LLMAuditorError: Error, Equatable {
    case badResponse
    case invalidAdvice
}

public actor LLMStrikeAuditor {
    private let transport: LLMTransport

    public init(transport: LLMTransport = URLSessionTransport()) {
        self.transport = transport
    }

    /// Advisory audit. Never authoritative; label must be rendered as opinion.
    public func audit(
        request: StrikeAuditRequest,
        provider: AIProvider,
        apiKey: String
    ) async throws -> StrikeAuditAdvice {
        let payload = try Self.buildRequest(request: request, provider: provider, apiKey: apiKey)
        let data = try await transport.post(url: payload.url, headers: payload.headers, body: payload.body)
        let content = try Self.extractContent(data: data, provider: provider)
        guard let advice = StrikeAuditAdvice.decode(fromJSON: content) else {
            throw LLMAuditorError.invalidAdvice
        }
        return advice
    }

    // MARK: - Pure request construction (testable)

    public struct RequestPayload: Sendable, Equatable {
        public var url: URL
        public var headers: [String: String]
        public var body: Data
    }

    public static func buildRequest(
        request: StrikeAuditRequest,
        provider: AIProvider,
        apiKey: String
    ) throws -> RequestPayload {
        let prompt = StrikeAuditPrompt.build(request: request)
        switch provider {
        case .deepseek:
            guard let url = URL(string: "https://api.deepseek.com/chat/completions") else {
                throw LLMAuditorError.badResponse
            }
            let payload: [String: Any] = [
                "model": provider.modelID,
                "messages": [
                    ["role": "system", "content": StrikeAuditPrompt.systemInstruction],
                    ["role": "user", "content": prompt],
                ],
                "response_format": ["type": "json_object"],
                "temperature": 0.1,
            ]
            let body = try JSONSerialization.data(withJSONObject: payload)
            return RequestPayload(
                url: url,
                headers: [
                    "Content-Type": "application/json",
                    "Authorization": "Bearer \(apiKey)",
                ],
                body: body
            )

        case .gemini:
            let endpoint = "https://generativelanguage.googleapis.com/v1beta/models/\(provider.modelID):generateContent"
            guard let url = URL(string: endpoint) else {
                throw LLMAuditorError.badResponse
            }
            let payload: [String: Any] = [
                "contents": [["parts": [["text": prompt]]]],
                "systemInstruction": ["parts": [["text": StrikeAuditPrompt.systemInstruction]]],
                "generationConfig": ["responseMimeType": "application/json", "temperature": 0.1],
            ]
            let body = try JSONSerialization.data(withJSONObject: payload)
            return RequestPayload(
                url: url,
                headers: [
                    "Content-Type": "application/json",
                    // Header, not a query parameter: URLs are frequently logged.
                    "x-goog-api-key": apiKey,
                ],
                body: body
            )
        }
    }

    // MARK: - Pure response extraction (testable)

    private struct DeepSeekEnvelope: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        let choices: [Choice]
    }

    private struct GeminiEnvelope: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable { let text: String }
                let parts: [Part]
            }
            let content: Content
        }
        let candidates: [Candidate]
    }

    public static func extractContent(data: Data, provider: AIProvider) throws -> String {
        switch provider {
        case .deepseek:
            guard let envelope = try? JSONDecoder().decode(DeepSeekEnvelope.self, from: data),
                  let content = envelope.choices.first?.message.content else {
                throw LLMAuditorError.badResponse
            }
            return content
        case .gemini:
            guard let envelope = try? JSONDecoder().decode(GeminiEnvelope.self, from: data),
                  let text = envelope.candidates.first?.content.parts.first?.text else {
                throw LLMAuditorError.badResponse
            }
            return text
        }
    }
}
