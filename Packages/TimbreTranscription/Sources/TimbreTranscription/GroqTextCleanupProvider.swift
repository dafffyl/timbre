import Foundation

/// Deuxième appel réseau après la transcription : passe le texte brut de
/// Whisper dans un modèle de chat rapide (`llama-3.1-8b-instant`, même
/// fournisseur que `GroqProvider` — pas de nouvelle dépendance) pour retirer
/// les hésitations et corriger la ponctuation, sans changer le sens.
/// Toujours optionnelle côté app (voir `DictationPreferences.cleanupEnabled`,
/// désactivée par défaut) — jamais requise pour obtenir un résultat.
public struct GroqTextCleanupProvider: TextCleanupProvider {
    private let apiKey: @Sendable () -> String?
    private let model: String
    private let endpoint: URL
    private let urlSession: URLSession

    public init(
        apiKey: @escaping @Sendable () -> String?,
        model: String = "llama-3.1-8b-instant",
        endpoint: URL = URL(string: "https://api.groq.com/openai/v1/chat/completions")!,
        urlSession: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.endpoint = endpoint
        self.urlSession = urlSession
    }

    public func cleanUp(_ request: TextCleanupRequest) async throws -> TextCleanupResult {
        guard let key = apiKey(), !key.isEmpty else {
            throw TextCleanupError.missingAPIKey
        }
        guard !request.text.isEmpty else {
            return TextCleanupResult(text: request.text)
        }

        return try await withRetry(shouldRetry: Self.isRetryable) {
            try await Self.performRequest(
                request,
                apiKey: key,
                model: model,
                endpoint: endpoint,
                urlSession: urlSession
            )
        }
    }

    private static func isRetryable(_ error: Error) -> Bool {
        guard let error = error as? TextCleanupError else { return false }
        switch error {
        case .network, .rateLimited:
            return true
        case .server(let statusCode, _):
            return statusCode >= 500
        default:
            return false
        }
    }

    private static func performRequest(
        _ request: TextCleanupRequest,
        apiKey: String,
        model: String,
        endpoint: URL,
        urlSession: URLSession
    ) async throws -> TextCleanupResult {
        let payload = ChatCompletionRequest(
            model: model,
            temperature: 0.2,
            messages: [
                .init(role: "system", content: systemPrompt(language: request.language)),
                .init(role: "user", content: request.text),
            ]
        )

        let bodyData: Data
        do {
            bodyData = try JSONEncoder().encode(payload)
        } catch {
            // Pratiquement inatteignable (que des `String` en entrée), mais
            // on préserve quand même le principe "erreurs typées, jamais de
            // `try?` silencieux" du projet plutôt que de forcer avec `try!`.
            throw TextCleanupError.decoding(error.localizedDescription)
        }

        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = bodyData

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: urlRequest)
        } catch {
            throw TextCleanupError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TextCleanupError.invalidResponse
        }

        switch http.statusCode {
        case 200..<300:
            break
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            throw TextCleanupError.rateLimited(retryAfter: retryAfter)
        default:
            throw TextCleanupError.server(statusCode: http.statusCode, message: String(data: data, encoding: .utf8))
        }

        do {
            let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content else {
                throw TextCleanupError.invalidResponse
            }
            return TextCleanupResult(text: content.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch let error as TextCleanupError {
            throw error
        } catch {
            throw TextCleanupError.decoding(error.localizedDescription)
        }
    }

    /// Instruction volontairement stricte ("ne réponds jamais au contenu") :
    /// un modèle de chat sans garde-fou explicite a tendance à répondre à ce
    /// que dit le texte plutôt qu'à le reformuler. Le risque n'est pas
    /// éliminé (aucune garantie dure côté modèle), seulement réduit — d'où
    /// le toggle désactivé par défaut tant que ce n'est pas éprouvé à
    /// l'usage (voir `DictationPreferences.cleanupEnabled`).
    private static func systemPrompt(language: String?) -> String {
        let languageHint = language.map { "Le texte est en \($0)." } ?? ""
        return """
        Tu nettoies une dictée vocale transcrite automatiquement. \(languageHint)
        Retire les hésitations et répétitions, corrige la ponctuation et la \
        casse, sans jamais changer le sens ni ajouter d'information. Ne \
        réponds jamais au contenu du texte, ne commente jamais : réponds \
        uniquement avec le texte nettoyé, rien d'autre.
        """
    }
}

private struct ChatCompletionRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }
    let model: String
    let temperature: Double
    let messages: [Message]
}

private struct ChatCompletionResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String
        }
        let message: Message
    }
    let choices: [Choice]
}
