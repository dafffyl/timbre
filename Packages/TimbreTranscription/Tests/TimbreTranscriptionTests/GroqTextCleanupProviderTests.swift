import Testing
import Foundation

@testable import TimbreTranscription

/// Imbriquée dans `GroqProviderTests` (via `extension`) plutôt qu'une suite
/// indépendante : `.serialized` ne sérialise que l'intérieur d'une suite,
/// pas deux suites différentes entre elles — deux suites au même niveau
/// tournant en parallèle se disputeraient le même `MockURLProtocol.requestHandler`
/// statique. Imbriquer sous la suite déjà `.serialized` étend cette garantie
/// à toute la hiérarchie, y compris cette suite ajoutée après coup.
extension GroqProviderTests {
    @Suite
    struct Cleanup {

        @Test func missingAPIKeyNeverHitsTheNetwork() async throws {
            let calledNetwork = Box(false)
            MockURLProtocol.requestHandler = { _ in
                calledNetwork.value = true
                throw URLError(.unknown)
            }

            let provider = GroqTextCleanupProvider(apiKey: { nil }, urlSession: MockURLProtocol.makeSession())

            await #expect(throws: TextCleanupError.missingAPIKey) {
                try await provider.cleanUp(TextCleanupRequest(text: "euh donc voilà"))
            }
            #expect(calledNetwork.value == false)
        }

        @Test func emptyTextNeverHitsTheNetwork() async throws {
            let calledNetwork = Box(false)
            MockURLProtocol.requestHandler = { _ in
                calledNetwork.value = true
                throw URLError(.unknown)
            }

            let provider = GroqTextCleanupProvider(apiKey: { "test-key" }, urlSession: MockURLProtocol.makeSession())
            let result = try await provider.cleanUp(TextCleanupRequest(text: ""))

            #expect(result.text == "")
            #expect(calledNetwork.value == false)
        }

        @Test func decodesCleanedTextFromChatCompletion() async throws {
            let json = Data("""
            {"choices": [{"message": {"content": "Voici le texte nettoyé."}}]}
            """.utf8)

            MockURLProtocol.requestHandler = { request in
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, json)
            }

            let provider = GroqTextCleanupProvider(apiKey: { "test-key" }, urlSession: MockURLProtocol.makeSession())
            let result = try await provider.cleanUp(TextCleanupRequest(text: "euh donc voilà quoi"))

            #expect(result.text == "Voici le texte nettoyé.")
        }

        @Test func requestUsesTheFastModelByDefaultAndSendsTheRawText() async throws {
            let json = Data("""
            {"choices": [{"message": {"content": "ok"}}]}
            """.utf8)

            let capturedBody = Box<Data?>(nil)
            MockURLProtocol.requestHandler = { request in
                capturedBody.value = request.httpBodyStreamData() ?? request.httpBody
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, json)
            }

            let provider = GroqTextCleanupProvider(apiKey: { "test-key" }, urlSession: MockURLProtocol.makeSession())
            _ = try await provider.cleanUp(TextCleanupRequest(text: "euh donc voilà quoi", language: "fr"))

            let bodyText = String(data: capturedBody.value ?? Data(), encoding: .utf8) ?? ""
            #expect(bodyText.contains("llama-3.1-8b-instant"))
            #expect(bodyText.contains("euh donc voilà quoi"))
        }

        @Test func mapsUnauthorizedStatusToServerError() async throws {
            MockURLProtocol.requestHandler = { request in
                let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
                return (response, Data("clé invalide".utf8))
            }

            let provider = GroqTextCleanupProvider(apiKey: { "bad-key" }, urlSession: MockURLProtocol.makeSession())

            await #expect(throws: TextCleanupError.self) {
                try await provider.cleanUp(TextCleanupRequest(text: "euh donc voilà"))
            }
        }
    }
}
