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

        @Test func missingAPIKeyNeverHitsTheNetwork() async {
            let called = Box(false)
            MockURLProtocol.requestHandler = { _ in
                called.value = true
                throw URLError(.unknown)
            }
            let provider = GroqMeetingSummaryProvider(apiKey: { nil }, urlSession: MockURLProtocol.makeSession())
            await #expect(throws: SummaryError.missingAPIKey) { try await provider.summarize(request()) }
            #expect(called.value == false)
        }

        @Test func emptyTranscriptIsRejected() async {
            let provider = GroqMeetingSummaryProvider(apiKey: { "k" }, urlSession: MockURLProtocol.makeSession())
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
            let provider = GroqMeetingSummaryProvider(apiKey: { "k" }, urlSession: MockURLProtocol.makeSession())
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
            let provider = GroqMeetingSummaryProvider(
                apiKey: { "k" }, maxCharactersPerChunk: 30, urlSession: MockURLProtocol.makeSession())
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
            let provider = GroqMeetingSummaryProvider(apiKey: { "k" }, urlSession: MockURLProtocol.makeSession())
            await #expect(throws: SummaryError.server(statusCode: 401, message: "{}")) {
                try await provider.summarize(request())
            }
            #expect(calls.value == 1)
        }
    }
}
