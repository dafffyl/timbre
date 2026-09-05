import Foundation

/// Provider Groq (`whisper-large-v3`, endpoint compatible OpenAI).
///
/// `apiKey` est une closure plutôt qu'une valeur figée à l'init : la clé
/// peut changer (l'utilisateur la modifie dans les réglages) sans qu'il
/// faille recréer le provider à chaque fois.
///
/// Schéma de réponse JSON de Groq déduit de la documentation publique, pas
/// encore vérifié contre un vrai appel — à ajuster dès le premier test réel
/// si les noms de champs diffèrent (`GroqTranscriptionResponse` ci-dessous).
public struct GroqProvider: TranscriptionProvider {
    public let identifier = ProviderIdentifier.groq
    public let capabilities = ProviderCapabilities(
        supportsNativeDiarization: false,
        supportsStreaming: false,
        wordTimestamps: true,
        maxFileSizeBytes: 25_000_000
    )

    private let apiKey: @Sendable () -> String?
    private let model: String
    private let endpoint: URL
    private let urlSession: URLSession

    public init(
        apiKey: @escaping @Sendable () -> String?,
        model: String = "whisper-large-v3",
        endpoint: URL = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!,
        urlSession: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.endpoint = endpoint
        self.urlSession = urlSession
    }

    public func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        guard let key = apiKey(), !key.isEmpty else {
            throw TranscriptionError.missingAPIKey
        }

        if let maxSize = capabilities.maxFileSizeBytes, request.audio.count > maxSize {
            throw TranscriptionError.fileTooLarge(maxBytes: maxSize)
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
        guard let error = error as? TranscriptionError else { return false }
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
        _ request: TranscriptionRequest,
        apiKey: String,
        model: String,
        endpoint: URL,
        urlSession: URLSession
    ) async throws -> TranscriptionResult {
        let boundary = "Boundary-\(UUID().uuidString)"
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = buildMultipartBody(
            audio: request.audio,
            model: model,
            language: request.language,
            prompt: request.prompt,
            boundary: boundary
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: urlRequest)
        } catch {
            throw TranscriptionError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.invalidResponse
        }

        switch http.statusCode {
        case 200..<300:
            break
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init)
            throw TranscriptionError.rateLimited(retryAfter: retryAfter)
        default:
            throw TranscriptionError.server(statusCode: http.statusCode, message: String(data: data, encoding: .utf8))
        }

        do {
            let decoded = try JSONDecoder().decode(GroqTranscriptionResponse.self, from: data)
            let words = (decoded.words ?? []).map {
                TranscriptionWord(text: $0.word, start: $0.start, end: $0.end)
            }
            return TranscriptionResult(text: decoded.text, words: words)
        } catch {
            throw TranscriptionError.decoding(error.localizedDescription)
        }
    }

    private static func buildMultipartBody(
        audio: Data,
        model: String,
        language: String?,
        prompt: String?,
        boundary: String
    ) -> Data {
        var body = Data()

        func appendField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        appendField(name: "model", value: model)
        appendField(name: "response_format", value: "verbose_json")
        appendField(name: "timestamp_granularities[]", value: "word")
        if let language {
            appendField(name: "language", value: language)
        }
        if let prompt {
            appendField(name: "prompt", value: prompt)
        }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/wav\r\n\r\n".data(using: .utf8)!)
        body.append(audio)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return body
    }
}

private struct GroqTranscriptionResponse: Decodable {
    let text: String
    let words: [GroqWord]?
}

private struct GroqWord: Decodable {
    let word: String
    let start: Double
    let end: Double
}
