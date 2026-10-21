import Foundation

/// Services de modèles de chat proposés pour le rapport (ADR-0009). Un cas
/// par *préréglage* : les quatre premiers ont une URL et des modèles connus,
/// `custom` laisse l'utilisateur saisir une URL OpenAI-compatible.
public enum SummaryService: String, Sendable, Codable, CaseIterable, Equatable {
    case groq, openAI, anthropic, baseten, custom

    public enum APIStyle: Sendable, Equatable {
        case openAICompatible
        case anthropic
    }

    public var displayName: String {
        switch self {
        case .groq: "Groq"
        case .openAI: "OpenAI"
        case .anthropic: "Claude (Anthropic)"
        case .baseten: "Baseten"
        case .custom: "Personnalisé"
        }
    }

    public var apiStyle: APIStyle {
        self == .anthropic ? .anthropic : .openAICompatible
    }

    /// `nil` pour `custom` : saisie par l'utilisateur.
    public var defaultBaseURL: URL? {
        switch self {
        case .groq: URL(string: "https://api.groq.com/openai/v1")
        case .openAI: URL(string: "https://api.openai.com/v1")
        case .anthropic: URL(string: "https://api.anthropic.com/v1")
        case .baseten: URL(string: "https://inference.baseten.co/v1")
        case .custom: nil
        }
    }

    /// Modèle utilisé tant que l'utilisateur n'en a pas choisi un autre.
    /// Vide quand aucune valeur sûre n'est connue : mieux vaut demander que
    /// deviner un identifiant qui finirait en 404 (modèles retirés).
    public var defaultModel: String {
        switch self {
        case .groq: "openai/gpt-oss-120b"
        case .anthropic: "claude-sonnet-5-5"
        case .openAI, .baseten, .custom: ""
        }
    }

    /// Repli affiché quand la liste en ligne n'est pas disponible.
    public var suggestedModels: [String] {
        switch self {
        case .groq: ["openai/gpt-oss-120b", "openai/gpt-oss-20b"]
        case .anthropic: ["claude-sonnet-5-5", "claude-haiku-5-5", "claude-opus-5-5"]
        case .openAI, .baseten, .custom: []
        }
    }

    /// Température envoyée : Groq garde la valeur historique du rapport,
    /// les autres laissent le défaut du modèle.
    public var temperature: Double? { self == .groq ? 0.3 : nil }

    /// `https` obligatoire (pas d'exception ATS, ADR-0009) et un hôte.
    public static func validatedBaseURL(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https",
            let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }
}

/// Fabrique le fournisseur de rapport d'un service. Pas d'I/O ici : la clé
/// est lue paresseusement par `apiKey` au moment de l'appel.
public enum MeetingSummaryProviderFactory {
    public static func make(
        service: SummaryService,
        model: String,
        customBaseURL: String = "",
        apiKey: @escaping @Sendable () -> String?,
        urlSession: URLSession = .shared
    ) throws -> any MeetingSummaryProvider {
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw SummaryError.missingModel }

        let baseURL: URL
        if let preset = service.defaultBaseURL {
            baseURL = preset
        } else if let custom = SummaryService.validatedBaseURL(customBaseURL) {
            baseURL = custom
        } else {
            throw SummaryError.invalidEndpoint
        }

        let client: any ChatCompletionClient
        switch service.apiStyle {
        case .anthropic:
            client = AnthropicChatClient(baseURL: baseURL, apiKey: apiKey, model: trimmedModel, urlSession: urlSession)
        case .openAICompatible:
            client = OpenAICompatibleChatClient(
                baseURL: baseURL, apiKey: apiKey, model: trimmedModel,
                temperature: service.temperature, urlSession: urlSession)
        }
        return ChatMeetingSummaryProvider(client: client)
    }
}

/// Liste les modèles d'un service (`GET {base}/models`) pour éviter de faire
/// saisir à la main des identifiants qui changent (modèles retirés → 404).
public struct ChatModelLister: Sendable {
    private let style: SummaryService.APIStyle
    private let baseURL: URL
    private let apiKey: @Sendable () -> String?
    private let urlSession: URLSession

    public init(
        style: SummaryService.APIStyle,
        baseURL: URL,
        apiKey: @escaping @Sendable () -> String?,
        urlSession: URLSession = .shared
    ) {
        self.style = style
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.urlSession = urlSession
    }

    public func listModels() async throws -> [String] {
        guard let key = apiKey(), !key.isEmpty else { throw SummaryError.missingAPIKey }

        var components = URLComponents(url: baseURL.appendingPathComponent("models"), resolvingAgainstBaseURL: false)
        if style == .anthropic { components?.queryItems = [URLQueryItem(name: "limit", value: "1000")] }
        guard let url = components?.url else { throw SummaryError.invalidEndpoint }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        switch style {
        case .openAICompatible:
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        case .anthropic:
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue(AnthropicChatClient.apiVersion, forHTTPHeaderField: "anthropic-version")
        }

        let data = try await ChatHTTP.send(request, urlSession: urlSession)
        let response: Response = try ChatHTTP.decode(data)
        return Self.chatModels(from: response.data.map(\.id))
    }

    private struct Response: Decodable {
        struct Item: Decodable { let id: String }
        let data: [Item]
    }

    /// Écarte les modèles qui ne font pas de chat (voix, embeddings, images,
    /// modération) : les listes OpenAI-compatibles mélangent tout.
    static func chatModels(from ids: [String]) -> [String] {
        let excluded = [
            "whisper", "embed", "tts", "transcribe", "dall-e", "image", "moderation", "guard", "audio",
            "realtime", "playai", "rerank", "speech",
        ]
        return ids
            .filter { id in !excluded.contains { id.lowercased().contains($0) } }
            .sorted()
    }
}
