import Foundation

/// Un aller-retour « consigne système + message → texte » vers un modèle de
/// chat. Seule couche qui connaît le format d'un service (ADR-0009) : le
/// découpage des transcripts et les prompts vivent dans
/// `ChatMeetingSummaryProvider`.
public protocol ChatCompletionClient: Sendable {
    func complete(system: String, user: String) async throws -> String
}

/// Services OpenAI-compatibles (`POST {base}/chat/completions`) : Groq,
/// OpenAI, Baseten et tout point d'accès personnalisé.
///
/// `temperature` est optionnelle et omise par défaut : certains modèles
/// (OpenAI de raisonnement) refusent toute valeur autre que la leur.
public struct OpenAICompatibleChatClient: ChatCompletionClient {
    private let baseURL: URL
    private let apiKey: @Sendable () -> String?
    private let model: String
    private let temperature: Double?
    private let urlSession: URLSession

    public init(
        baseURL: URL,
        apiKey: @escaping @Sendable () -> String?,
        model: String,
        temperature: Double? = nil,
        urlSession: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.temperature = temperature
        self.urlSession = urlSession
    }

    public func complete(system: String, user: String) async throws -> String {
        guard let key = apiKey(), !key.isEmpty else { throw SummaryError.missingAPIKey }
        let payload = Request(
            model: model, temperature: temperature,
            messages: [.init(role: "system", content: system), .init(role: "user", content: user)])

        var request = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try ChatHTTP.encode(payload)
        request.timeoutInterval = 120

        let data = try await ChatHTTP.send(request, urlSession: urlSession)
        let response: Response = try ChatHTTP.decode(data)
        return try ChatHTTP.nonEmpty(response.choices.first?.message.content)
    }

    private struct Request: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        let model: String
        let temperature: Double?
        let messages: [Message]
    }

    private struct Response: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message
        }
        let choices: [Choice]
    }
}

/// API Messages d'Anthropic (`POST {base}/messages`) : authentification par
/// `x-api-key`, consigne système séparée des messages, réponse en blocs.
public struct AnthropicChatClient: ChatCompletionClient {
    static let apiVersion = "2023-06-01"

    private let baseURL: URL
    private let apiKey: @Sendable () -> String?
    private let model: String
    private let maxTokens: Int
    private let urlSession: URLSession

    public init(
        baseURL: URL = URL(string: "https://api.anthropic.com/v1")!,
        apiKey: @escaping @Sendable () -> String?,
        model: String,
        maxTokens: Int = 8_192,
        urlSession: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
        self.urlSession = urlSession
    }

    public func complete(system: String, user: String) async throws -> String {
        guard let key = apiKey(), !key.isEmpty else { throw SummaryError.missingAPIKey }
        let payload = Request(
            model: model, max_tokens: maxTokens, system: system,
            messages: [.init(role: "user", content: user)])

        var request = URLRequest(url: baseURL.appendingPathComponent("messages"))
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try ChatHTTP.encode(payload)
        request.timeoutInterval = 120

        let data = try await ChatHTTP.send(request, urlSession: urlSession)
        let response: Response = try ChatHTTP.decode(data)
        let text = response.content.compactMap { $0.type == "text" ? $0.text : nil }.joined()
        return try ChatHTTP.nonEmpty(text)
    }

    // Les noms de champs suivent le JSON de l'API (snake_case).
    private struct Request: Encodable {
        struct Message: Encodable {
            let role: String
            let content: String
        }
        let model: String
        let max_tokens: Int
        let system: String
        let messages: [Message]
    }

    private struct Response: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }
        let content: [Block]
    }
}

/// Envoi, nouvelles tentatives et correspondance code HTTP → `SummaryError`,
/// communs aux deux formats.
enum ChatHTTP {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try JSONEncoder().encode(value)
        } catch {
            throw SummaryError.decoding(error.localizedDescription)
        }
    }

    static func decode<T: Decodable>(_ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw SummaryError.decoding(error.localizedDescription)
        }
    }

    static func nonEmpty(_ text: String?) throws -> String {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { throw SummaryError.invalidResponse }
        return trimmed
    }

    static func send(_ request: URLRequest, urlSession: URLSession) async throws -> Data {
        try await withRetry(shouldRetry: isRetryable) {
            try await perform(request, urlSession: urlSession)
        }
    }

    private static func isRetryable(_ error: Error) -> Bool {
        guard let error = error as? SummaryError else { return false }
        switch error {
        case .network, .rateLimited: return true
        case .server(let statusCode, _): return statusCode >= 500
        default: return false
        }
    }

    private static func perform(_ request: URLRequest, urlSession: URLSession) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw SummaryError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw SummaryError.invalidResponse }

        switch http.statusCode {
        case 200..<300:
            return data
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            throw SummaryError.rateLimited(retryAfter: retryAfter)
        default:
            throw SummaryError.server(statusCode: http.statusCode, message: String(data: data, encoding: .utf8))
        }
    }
}
