//
//  MeetingTranscriptionController.swift
//  Timbre
//

import Foundation
import AVFoundation
import TimbreSecurity
import TimbreTranscription
import TimbreDiarization

enum MeetingTranscriptionError: Error {
    case cannotCreateExportSession
}

/// Orchestre le pipeline complet décrit dans ADR-0005 : diarisation sur le
/// fichier entier et chunking+transcription tournent concurremment
/// (`async let`), jamais l'inverse (diariser chunk par chunk donnerait des
/// identifiants de locuteur incohérents d'un chunk à l'autre — voir l'ADR).
@MainActor
@Observable
final class MeetingTranscriptionController {
    enum State: Equatable {
        case idle
        case diarizing
        case transcribing(chunk: Int, of: Int)
        case aligning
        case done([SpeakerTurn])
        case failed(String)
    }

    private(set) var state: State = .idle

    private let diarizationProvider: any DiarizationProvider
    private let transcriptionProvider: any TranscriptionProvider

    /// Bitrate de nos propres enregistrements (`BackgroundRecorder`, 32 kbps)
    /// — pas une estimation : on contrôle nous-mêmes tout l'encodage de bout
    /// en bout tant qu'il n'y a pas d'import de fichier externe (ADR-0005).
    private let bitrateForChunking: Double
    private let sizeLimitBytes: Int

    init(
        diarizationProvider: any DiarizationProvider = FluidAudioDiarizationProvider(),
        transcriptionProvider: any TranscriptionProvider = GroqProvider(apiKey: { (try? APIKeyStore().load()) ?? nil }),
        bitrateForChunking: Double = 32_000,
        sizeLimitBytes: Int = 25_000_000
    ) {
        self.diarizationProvider = diarizationProvider
        self.transcriptionProvider = transcriptionProvider
        self.bitrateForChunking = bitrateForChunking
        self.sizeLimitBytes = sizeLimitBytes
    }

    /// Échoue entièrement plutôt que produire un transcript à trous si un
    /// chunk ou la diarisation échoue (ADR-0005, cas limites 1 et 2) — un
    /// raffinement "reprendre ce qui a échoué" est possible plus tard si le
    /// besoin se confirme à l'usage.
    func run(audioURL: URL) async {
        state = .diarizing
        do {
            async let segmentsTask = diarizationProvider.diarize(audioURL)
            let words = try await transcribeAllChunks(audioURL: audioURL)
            let segments = try await segmentsTask

            state = .aligning
            let attributed = SpeakerAlignment.align(words: words, segments: segments)
            let turns = TranscriptFormatter.groupIntoTurns(attributed)
            state = .done(turns)
        } catch {
            state = .failed(Self.userMessage(for: error))
        }
    }

    private func transcribeAllChunks(audioURL: URL) async throws -> [TranscriptionWord] {
        let asset = AVURLAsset(url: audioURL)
        let duration = try await asset.load(.duration).seconds
        let maxChunkDuration = AudioChunker.maxDuration(
            forBitrateBitsPerSecond: bitrateForChunking,
            sizeLimitBytes: sizeLimitBytes
        )
        let plans = AudioChunker.plan(totalDuration: duration, maxChunkDuration: maxChunkDuration, overlap: 10)

        var chunks: [TranscribedChunk] = []
        for (index, plan) in plans.enumerated() {
            state = .transcribing(chunk: index + 1, of: plans.count)
            let chunkURL = try await Self.exportChunk(from: audioURL, range: plan)
            defer { try? FileManager.default.removeItem(at: chunkURL) }

            let data = try Data(contentsOf: chunkURL)
            let result = try await transcriptionProvider.transcribe(
                TranscriptionRequest(audio: data, format: .m4a, language: "fr")
            )
            chunks.append(TranscribedChunk(plan: plan, words: result.words))
        }
        return TranscriptStitcher.stitch(chunks)
    }

    /// API vérifiée en la faisant tourner réellement (ADR-0005) :
    /// `export(to:as:) async throws` — la variante à base de
    /// `outputURL`/`outputFileType` + callback est dépréciée sur ce SDK.
    private static func exportChunk(from sourceURL: URL, range: AudioChunkPlan) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw MeetingTranscriptionError.cannotCreateExportSession
        }
        export.timeRange = CMTimeRange(
            start: CMTime(seconds: range.start, preferredTimescale: 600),
            end: CMTime(seconds: range.end, preferredTimescale: 600)
        )
        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        try await export.export(to: outputURL, as: .m4a)
        return outputURL
    }

    private static func userMessage(for error: Error) -> String {
        guard let error = error as? TranscriptionError else {
            return "Échec de la transcription de la réunion."
        }
        switch error {
        case .missingAPIKey:
            return "Clé API Groq manquante — configure-la dans les réglages."
        case .network:
            return "Problème réseau pendant la transcription."
        case .rateLimited:
            return "Trop de requêtes envoyées à Groq — réessaie dans un instant."
        default:
            return "Erreur pendant la transcription de la réunion."
        }
    }
}
