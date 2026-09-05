import Testing
import Foundation

@testable import TimbreTranscription

/// `.serialized` : ces tests partagent `MockURLProtocol.requestHandler`
/// (état global unique) — en parallèle, un test écraserait le handler d'un
/// autre avant que sa propre requête ne parte.
@Suite(.serialized)
struct GroqProviderTests {

    @Test func missingAPIKeyNeverHitsTheNetwork() async throws {
        let calledNetwork = Box(false)
        MockURLProtocol.requestHandler = { _ in
            calledNetwork.value = true
            throw URLError(.unknown)
        }

        let provider = GroqProvider(apiKey: { nil }, urlSession: MockURLProtocol.makeSession())

        await #expect(throws: TranscriptionError.missingAPIKey) {
            try await provider.transcribe(TranscriptionRequest(audio: Data()))
        }
        #expect(calledNetwork.value == false)
    }

    @Test func fileTooLargeNeverHitsTheNetwork() async throws {
        let calledNetwork = Box(false)
        MockURLProtocol.requestHandler = { _ in
            calledNetwork.value = true
            throw URLError(.unknown)
        }

        let provider = GroqProvider(apiKey: { "test-key" }, urlSession: MockURLProtocol.makeSession())
        let oversized = Data(count: 26_000_000)

        await #expect(throws: TranscriptionError.fileTooLarge(maxBytes: 25_000_000)) {
            try await provider.transcribe(TranscriptionRequest(audio: oversized))
        }
        #expect(calledNetwork.value == false)
    }

    @Test func decodesSuccessfulResponseWithWordTimestamps() async throws {
        let json = Data("""
        {"text": "bonjour le monde", "words": [{"word": "bonjour", "start": 0.0, "end": 0.42}]}
        """.utf8)

        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let provider = GroqProvider(apiKey: { "test-key" }, urlSession: MockURLProtocol.makeSession())
        let result = try await provider.transcribe(TranscriptionRequest(audio: Data([0x00])))

        #expect(result.text == "bonjour le monde")
        #expect(result.words.count == 1)
        #expect(result.words.first?.text == "bonjour")
        #expect(result.words.first?.end == 0.42)
    }

    @Test func mapsUnauthorizedStatusToServerError() async throws {
        MockURLProtocol.requestHandler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, Data("clé invalide".utf8))
        }

        let provider = GroqProvider(apiKey: { "bad-key" }, urlSession: MockURLProtocol.makeSession())

        await #expect(throws: TranscriptionError.self) {
            try await provider.transcribe(TranscriptionRequest(audio: Data([0x00])))
        }
    }

    @Test func requestIncludesModelAndWordTimestampFields() async throws {
        let json = Data("""
        {"text": ""}
        """.utf8)

        let capturedBody = Box<Data?>(nil)
        MockURLProtocol.requestHandler = { request in
            capturedBody.value = request.httpBodyStreamData() ?? request.httpBody
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let provider = GroqProvider(apiKey: { "test-key" }, urlSession: MockURLProtocol.makeSession())
        _ = try await provider.transcribe(TranscriptionRequest(audio: Data([0x00]), language: "fr", prompt: "vocabulaire technique"))

        let bodyText = String(data: capturedBody.value ?? Data(), encoding: .utf8) ?? ""
        #expect(bodyText.contains("name=\"model\""))
        #expect(bodyText.contains("whisper-large-v3"))
        #expect(bodyText.contains("timestamp_granularities[]"))
        #expect(bodyText.contains("name=\"language\""))
        #expect(bodyText.contains("vocabulaire technique"))
    }
}

extension URLRequest {
    /// `URLProtocol` reçoit parfois le corps via un flux plutôt que
    /// `httpBody` selon le chemin interne emprunté par `URLSession` — on lit
    /// les deux pour ne pas dépendre de ce détail d'implémentation.
    fileprivate func httpBodyStreamData() -> Data? {
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}
