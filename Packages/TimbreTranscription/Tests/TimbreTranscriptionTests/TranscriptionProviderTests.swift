import Testing
import Foundation

@testable import TimbreTranscription

/// Fonction écrite contre le protocole seul, jamais contre un provider
/// concret — c'est exactement ce que fera le vrai code applicatif plus tard.
/// Si ça compile et fonctionne avec `FakeTranscriptionProvider`, l'abstraction
/// est utilisable avant même que Groq existe.
private func performDictation(using provider: any TranscriptionProvider, audio: Data) async throws -> String {
    let result = try await provider.transcribe(TranscriptionRequest(audio: audio))
    return result.text
}

@Test func abstractionWorksAgainstProtocolTypeAlone() async throws {
    let provider = FakeTranscriptionProvider(result: .success(TranscriptionResult(text: "bonjour")))
    let text = try await performDictation(using: provider, audio: Data([0x01, 0x02]))
    #expect(text == "bonjour")
}

@Test func abstractionPropagatesTypedErrors() async throws {
    let provider = FakeTranscriptionProvider(result: .failure(.missingAPIKey))

    await #expect(throws: TranscriptionError.missingAPIKey) {
        try await performDictation(using: provider, audio: Data())
    }
}

@Test func providerReceivesTheExactRequestSent() async throws {
    let provider = FakeTranscriptionProvider(result: .success(TranscriptionResult(text: "")))
    let audio = Data([0xAA, 0xBB])
    _ = try await performDictation(using: provider, audio: audio)

    let received = await provider.receivedRequests
    #expect(received.count == 1)
    #expect(received.first?.audio == audio)
}

@Test func capabilitiesAreExposedWithoutCallingTranscribe() {
    let capabilities = ProviderCapabilities(
        supportsNativeDiarization: true,
        supportsStreaming: false,
        wordTimestamps: true,
        maxFileSizeBytes: 25_000_000
    )
    let provider = FakeTranscriptionProvider(capabilities: capabilities, result: .success(TranscriptionResult(text: "")))

    #expect(provider.capabilities.supportsNativeDiarization)
    #expect(provider.capabilities.maxFileSizeBytes == 25_000_000)
}

@Test func resultWithoutWordsIsValidWhenCapabilityIsFalse() {
    let result = TranscriptionResult(text: "sans horodatage")
    #expect(result.words.isEmpty)
}
