import Foundation
import Testing

@testable import TimbreTranscription

@Suite struct TranscriptChunkerTests {
    @Test func shortTextIsASingleChunk() {
        #expect(TranscriptChunker.split("bonjour", maxCharacters: 100) == ["bonjour"])
    }

    @Test func splitsBetweenParagraphsWithoutCuttingThem() {
        let text = "aaaa bbbb\n\ncccc dddd\n\neeee ffff"
        let chunks = TranscriptChunker.split(text, maxCharacters: 20)
        #expect(chunks == ["aaaa bbbb\n\ncccc dddd", "eeee ffff"])
        #expect(chunks.allSatisfy { $0.count <= 20 })
    }

    @Test func oversizedParagraphIsSplitOnWords() {
        let text = Array(repeating: "mot", count: 20).joined(separator: " ")
        let chunks = TranscriptChunker.split(text, maxCharacters: 15)
        #expect(chunks.allSatisfy { $0.count <= 15 })
        #expect(chunks.joined(separator: " ") == text)
    }
}

extension GroqProviderTests {
    @Suite
    struct MeetingSummary {
        private func request(_ transcript: String = "Locuteur 1 :\nbonjour") -> MeetingSummaryRequest {
            MeetingSummaryRequest(transcript: transcript, instructions: "Liste les actions.", outputLanguage: "français")
        }

        private func provider(apiKey: String?, maxCharactersPerChunk: Int = 40_000) -> ChatMeetingSummaryProvider {
            ChatMeetingSummaryProvider(
                client: OpenAICompatibleChatClient(
                    baseURL: URL(string: "https://example.test/v1")!, apiKey: { apiKey }, model: "m",
                    urlSession: MockURLProtocol.makeSession()),
                maxCharactersPerChunk: maxCharactersPerChunk)
        }

        @Test func missingAPIKeyNeverHitsTheNetwork() async {
            let called = Box(false)
            MockURLProtocol.requestHandler = { _ in
                called.value = true
                throw URLError(.unknown)
            }
            let provider = provider(apiKey: nil)
            await #expect(throws: SummaryError.missingAPIKey) { try await provider.summarize(request()) }
            #expect(called.value == false)
        }

        @Test func emptyTranscriptIsRejected() async {
            let provider = provider(apiKey: "k")
            await #expect(throws: SummaryError.emptyTranscript) { try await provider.summarize(request("  \n")) }
        }

        @Test func sendsUserInstructionsAndWrappedTranscript() async throws {
            let captured = Box<Data?>(nil)
            MockURLProtocol.requestHandler = { request in
                captured.value = request.httpBody ?? request.httpBodyStream.flatMap { stream in
                    stream.open()
                    defer { stream.close() }
                    var data = Data()
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable {
                        let count = stream.read(&buffer, maxLength: buffer.count)
                        if count <= 0 { break }
                        data.append(buffer, count: count)
                    }
                    return data
                }
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data("{\"choices\":[{\"message\":{\"content\":\"## Rapport\"}}]}".utf8))
            }
            let provider = provider(apiKey: "k")
            let result = try await provider.summarize(request())

            #expect(result == "## Rapport")
            let body = String(data: try #require(captured.value), encoding: .utf8) ?? ""
            #expect(body.contains("Liste les actions."))
            #expect(body.contains("<transcript>"))
            #expect(body.contains("français"))
        }

        @Test func longTranscriptIsSummarizedInPartsThenCombined() async throws {
            let calls = Box(0)
            MockURLProtocol.requestHandler = { request in
                calls.value += 1
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                return (response, Data(#"{"choices":[{"message":{"content":"notes"}}]}"#.utf8))
            }
            let provider = provider(apiKey: "k", maxCharactersPerChunk: 30)
            let transcript = "aaaa bbbb cccc dddd\n\neeee ffff gggg hhhh\n\niiii jjjj kkkk llll"
            _ = try await provider.summarize(request(transcript))
            // 3 tranches + 1 appel final
            #expect(calls.value == 4)
        }

        @Test func authErrorIsNotRetried() async {
            let calls = Box(0)
            MockURLProtocol.requestHandler = { request in
                calls.value += 1
                let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!
                return (response, Data("{}".utf8))
            }
            let provider = provider(apiKey: "k")
            await #expect(throws: SummaryError.server(statusCode: 401, message: "{}")) {
                try await provider.summarize(request())
            }
            #expect(calls.value == 1)
        }
    }
}

func bodyString(of request: URLRequest) -> String {
    let data =
        request.httpBody
        ?? request.httpBodyStream.flatMap { stream -> Data in
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            return data
        }
    return String(data: data ?? Data(), encoding: .utf8) ?? ""
}

extension GroqProviderTests {
    @Suite
    struct SummaryServices {
        private let ok = #"{"choices":[{"message":{"content":"ok"}}]}"#

        @Test func openAICompatibleHitsChatCompletionsWithBearerAndNoTemperature() async throws {
            let captured = Box<URLRequest?>(nil)
            let body = Box("")
            MockURLProtocol.requestHandler = { [ok] request in
                captured.value = request
                body.value = bodyString(of: request)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(ok.utf8))
            }
            let client = OpenAICompatibleChatClient(
                baseURL: URL(string: "https://api.example.test/v1")!, apiKey: { "sk-1" }, model: "gpt-x",
                urlSession: MockURLProtocol.makeSession())
            #expect(try await client.complete(system: "s", user: "u") == "ok")
            let request = try #require(captured.value)
            #expect(request.url?.absoluteString == "https://api.example.test/v1/chat/completions")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer sk-1")
            #expect(!body.value.contains("temperature"))
            #expect(body.value.contains("\"model\":\"gpt-x\""))
        }

        @Test func anthropicUsesMessagesEndpointKeyHeaderAndSeparateSystem() async throws {
            let captured = Box<URLRequest?>(nil)
            let body = Box("")
            MockURLProtocol.requestHandler = { request in
                captured.value = request
                body.value = bodyString(of: request)
                let json = #"{"content":[{"type":"text","text":"Bonjour "},{"type":"text","text":"monde"}]}"#
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
            }
            let client = AnthropicChatClient(apiKey: { "ak" }, model: "claude-x", urlSession: MockURLProtocol.makeSession())
            #expect(try await client.complete(system: "SYS", user: "USER") == "Bonjour monde")
            let request = try #require(captured.value)
            #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
            #expect(request.value(forHTTPHeaderField: "x-api-key") == "ak")
            #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(body.value.contains("\"system\":\"SYS\""))
            #expect(body.value.contains("\"max_tokens\""))
        }

        @Test func notFoundIsReportedAsServerErrorWithoutRetry() async {
            let calls = Box(0)
            MockURLProtocol.requestHandler = { request in
                calls.value += 1
                return (HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
            }
            let client = OpenAICompatibleChatClient(
                baseURL: URL(string: "https://api.example.test/v1")!, apiKey: { "k" }, model: "gone",
                urlSession: MockURLProtocol.makeSession())
            await #expect(throws: SummaryError.server(statusCode: 404, message: "{}")) {
                try await client.complete(system: "s", user: "u")
            }
            #expect(calls.value == 1)
        }

        @Test func modelListingFiltersNonChatModelsAndSorts() async throws {
            let captured = Box<URLRequest?>(nil)
            MockURLProtocol.requestHandler = { request in
                captured.value = request
                let json = #"{"data":[{"id":"whisper-large-v3"},{"id":"zeta-chat"},{"id":"alpha-chat"},{"id":"text-embedding-3"},{"id":"llama-guard-4"}]}"#
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
            }
            let lister = ChatModelLister(
                style: .openAICompatible, baseURL: URL(string: "https://api.example.test/v1")!,
                apiKey: { "k" }, urlSession: MockURLProtocol.makeSession())
            #expect(try await lister.listModels() == ["alpha-chat", "zeta-chat"])
            #expect(captured.value?.url?.absoluteString == "https://api.example.test/v1/models")
        }

        @Test func anthropicModelListingSendsKeyHeaders() async throws {
            let captured = Box<URLRequest?>(nil)
            MockURLProtocol.requestHandler = { request in
                captured.value = request
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, Data(#"{"data":[{"id":"claude-a"}]}"#.utf8))
            }
            let lister = ChatModelLister(
                style: .anthropic, baseURL: URL(string: "https://api.anthropic.com/v1")!,
                apiKey: { "ak" }, urlSession: MockURLProtocol.makeSession())
            #expect(try await lister.listModels() == ["claude-a"])
            #expect(captured.value?.value(forHTTPHeaderField: "x-api-key") == "ak")
            #expect(captured.value?.url?.query == "limit=1000")
        }

        @Test func factoryRejectsMissingModelAndBadCustomURL() {
            #expect(throws: SummaryError.missingModel) {
                try MeetingSummaryProviderFactory.make(service: .openAI, model: " ", apiKey: { "k" })
            }
            #expect(throws: SummaryError.invalidEndpoint) {
                try MeetingSummaryProviderFactory.make(
                    service: .custom, model: "m", customBaseURL: "http://localhost:11434/v1", apiKey: { "k" })
            }
            #expect(throws: Never.self) {
                _ = try MeetingSummaryProviderFactory.make(
                    service: .custom, model: "m", customBaseURL: "https://api.mistral.ai/v1", apiKey: { "k" })
            }
        }

        @Test func customURLMustBeHTTPSWithAHost() {
            #expect(SummaryService.validatedBaseURL("https://a.example/v1") != nil)
            #expect(SummaryService.validatedBaseURL("http://a.example/v1") == nil)
            #expect(SummaryService.validatedBaseURL("https://") == nil)
            #expect(SummaryService.validatedBaseURL("pas une url") == nil)
        }

        @Test func presetsHaveNoDeprecatedGroqModels() {
            #expect(!SummaryService.groq.defaultModel.contains("llama-3"))
            #expect(SummaryService.groq.suggestedModels.allSatisfy { !$0.contains("llama-3") })
        }

        @Test func formatGuidanceReachesTheSystemPrompt() {
            let request = MeetingSummaryRequest(
                transcript: "x", instructions: "Ton formel.", outputLanguage: "français", format: .short)
            let prompt = ChatMeetingSummaryProvider.reportSystemPrompt(request)
            #expect(prompt.contains("5 lignes"))
            #expect(prompt.contains("Ton formel."))
            let free = MeetingSummaryRequest(transcript: "x", instructions: "", outputLanguage: "français")
            #expect(!ChatMeetingSummaryProvider.reportSystemPrompt(free).contains("Format de sortie"))
        }
    }
}
