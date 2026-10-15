//
//  MeetingTranscriptionControllerTests.swift
//  TimbreTests
//

import Foundation
import Testing
import TimbreDiarization
import TimbreTranscription

@testable import Timbre

private struct StubDiarizer: DiarizationProvider {
    func prepareModels() async throws {}
    func diarize(_ audioURL: URL) async throws -> [SpeakerSegment] { [] }
}

private struct StubTranscriber: TranscriptionProvider {
    let identifier = ProviderIdentifier.groq
    let capabilities = ProviderCapabilities(
        supportsNativeDiarization: false,
        supportsStreaming: false,
        wordTimestamps: true
    )
    let error: TranscriptionError

    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult {
        throw error
    }
}

@MainActor
struct MeetingTranscriptionControllerTests {
    @Test func modelsNotReadyFailsWithoutDiarizing() async {
        let controller = MeetingTranscriptionController(
            diarizationProvider: StubDiarizer(),
            ensureModelsReady: { .needsConsent },
            transcriptionProvider: StubTranscriber(error: .network("offline"))
        )

        await controller.run(audioURL: URL(fileURLWithPath: "/dev/null"))

        guard case .failed = controller.state else {
            Issue.record("État inattendu : \(controller.state)")
            return
        }
    }

    @Test func modelsFailureKeepsAudioRetryable() async {
        let controller = MeetingTranscriptionController(
            diarizationProvider: StubDiarizer(),
            ensureModelsReady: { .failed("réseau") },
            transcriptionProvider: StubTranscriber(error: .network("offline"))
        )

        await controller.run(audioURL: URL(fileURLWithPath: "/dev/null"))

        guard case .failed(let message) = controller.state else {
            Issue.record("État inattendu : \(controller.state)")
            return
        }
        #expect(message.contains("conservé"))
    }
}
