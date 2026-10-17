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
        /// `hadMissingChunks` : au moins un chunk a échoué et a été
        /// remplacé par un marqueur (voir ADR-0005, cas limite 1 révisé) —
        /// permet d'afficher un avertissement ponctuel, le marqueur lui-même
        /// reste visible dans `turns` de toute façon.
        case done(turns: [SpeakerTurn], hadMissingChunks: Bool, speakerVoices: [SpeakerID: SpeakerVoice])
        case failed(String)
        /// Pipeline interrompu (vue quittée, tâche annulée) : ni échec ni
        /// résultat — l'appelant doit conserver l'audio.
        case cancelled
    }

    private(set) var state: State = .idle

    private let diarizationProvider: any DiarizationProvider
    private let transcriptionProvider: any TranscriptionProvider
    /// Passe par le coordinateur de provisionnement (ADR-0004) plutôt que de
    /// laisser `diarize` télécharger ~500 Mo implicitement, sans consentement
    /// ni vérification du Wi-Fi.
    private let ensureModelsReady: @Sendable () async -> ModelProvisioningState

    /// Bitrate de nos propres enregistrements (`BackgroundRecorder`, 32 kbps)
    /// — pas une estimation : on contrôle nous-mêmes tout l'encodage de bout
    /// en bout tant qu'il n'y a pas d'import de fichier externe (ADR-0005).
    private let bitrateForChunking: Double
    private let sizeLimitBytes: Int

    init(
        diarizationProvider: any DiarizationProvider = DiarizationEnvironment.diarizationProvider,
        ensureModelsReady: @escaping @Sendable () async -> ModelProvisioningState = {
            await DiarizationEnvironment.provisioningCoordinator.ensureModelsReady()
        },
        transcriptionProvider: any TranscriptionProvider = GroqProvider(apiKey: { (try? APIKeyStore().load()) ?? nil }),
        bitrateForChunking: Double = 32_000,
        sizeLimitBytes: Int = 25_000_000
    ) {
        self.diarizationProvider = diarizationProvider
        self.ensureModelsReady = ensureModelsReady
        self.transcriptionProvider = transcriptionProvider
        self.bitrateForChunking = bitrateForChunking
        self.sizeLimitBytes = sizeLimitBytes
    }

    /// La diarisation qui échoue fait toujours échouer toute la réunion
    /// (ADR-0005, cas limite 2 : nature de problème différente, pas un aléa
    /// réseau ponctuel). Un chunk de transcription qui échoue, lui, dégrade
    /// vers un marqueur plutôt que d'interrompre tout le pipeline (cas
    /// limite 1, révisé) — sauf `missingAPIKey`, qui échouera de façon
    /// identique et déterministe sur chaque chunk restant : autant arrêter
    /// tout de suite plutôt que gaspiller du temps à le redécouvrir N fois.
    func run(audioURL: URL) async {
        state = .diarizing
        do {
            switch await ensureModelsReady() {
            case .ready:
                break
            case .needsConsent, .needsWiFi:
                state = .failed(String(localized: "Les modèles d'analyse des locuteurs ne sont pas installés — prépare-les dans les réglages (Wi-Fi requis). L'enregistrement est conservé."))
                return
            case .failed:
                state = .failed(String(localized: "Impossible de préparer l'analyse des locuteurs. L'enregistrement est conservé, réessaie."))
                return
            }
            async let diarizationTask = diarizationProvider.diarizeDetailed(audioURL)
            let (words, hadMissingChunks) = try await transcribeAllChunks(audioURL: audioURL)
            let diarization = try await diarizationTask
            let segments = diarization.segments

            state = .aligning
            let attributed = SpeakerAlignment.align(words: words, segments: segments)
            let turns = TranscriptFormatter.groupIntoTurns(attributed)
            state = .done(turns: turns, hadMissingChunks: hadMissingChunks, speakerVoices: diarization.speakerVoices)
        } catch is CancellationError {
            state = .cancelled
        } catch TranscriptionError.cancelled {
            state = .cancelled
        } catch {
            state = .failed(Self.userMessage(for: error))
        }
    }

    private func transcribeAllChunks(audioURL: URL) async throws -> (words: [TranscriptionWord], hadMissingChunks: Bool) {
        let asset = AVURLAsset(url: audioURL)
        let duration = try await asset.load(.duration).seconds
        let maxChunkDuration = AudioChunker.maxDuration(
            forBitrateBitsPerSecond: bitrateForChunking,
            sizeLimitBytes: sizeLimitBytes
        )
        let plans = AudioChunker.plan(totalDuration: duration, maxChunkDuration: maxChunkDuration, overlap: 10)

        let language = DictationPreferences.languageCode
        var chunks: [TranscribedChunk] = []
        var hadMissingChunks = false
        for (index, plan) in plans.enumerated() {
            state = .transcribing(chunk: index + 1, of: plans.count)
            do {
                let chunkURL = try await Self.exportChunk(from: audioURL, range: plan)
                defer { try? FileManager.default.removeItem(at: chunkURL) }

                let data = try Data(contentsOf: chunkURL)
                let result = try await transcriptionProvider.transcribe(
                    TranscriptionRequest(audio: data, format: .m4a, language: language)
                )
                chunks.append(TranscribedChunk(plan: plan, words: result.words))
            } catch TranscriptionError.missingAPIKey {
                throw TranscriptionError.missingAPIKey
            } catch is CancellationError {
                throw CancellationError()
            } catch TranscriptionError.cancelled {
                throw TranscriptionError.cancelled
            } catch TranscriptionError.server(let statusCode, let message) where statusCode == 401 || statusCode == 403 {
                // Clé refusée : déterministe, chaque chunk échouerait pareil.
                throw TranscriptionError.server(statusCode: statusCode, message: message)
            } catch {
                hadMissingChunks = true
                chunks.append(TranscribedChunk(plan: plan, words: [Self.missingChunkMarker(for: plan)]))
            }
        }
        return (TranscriptStitcher.stitch(chunks), hadMissingChunks)
    }

    /// Horodatage local au chunk (0 à sa durée) — `TranscriptStitcher`
    /// décale par `plan.start` comme n'importe quel autre mot, et
    /// `SpeakerAlignment` l'attribue à un locuteur comme n'importe quel
    /// autre mot : le trou reste visible en clair dans le transcript plutôt
    /// que silencieusement absent.
    private static func missingChunkMarker(for plan: AudioChunkPlan) -> TranscriptionWord {
        // Au milieu du chunk, pas à 0 : à 0 le marqueur tombe dans la zone de
        // recouvrement et `TranscriptStitcher` le supprime pour tout chunk
        // autre que le premier.
        let middle = (plan.end - plan.start) / 2
        return TranscriptionWord(text: String(localized: "[transcription indisponible]"), start: middle, end: middle + 0.1)
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
            return String(localized: "Échec de la transcription de la réunion.")
        }
        switch error {
        case .missingAPIKey:
            return String(localized: "Clé API Groq manquante — configure-la dans les réglages.")
        case .network:
            return String(localized: "Problème réseau pendant la transcription.")
        case .rateLimited:
            return String(localized: "Trop de requêtes envoyées à Groq — réessaie dans un instant.")
        case .server(let statusCode, _) where statusCode == 401 || statusCode == 403:
            return String(localized: "Clé API Groq refusée (code \(statusCode)) — vérifie-la dans les réglages.")
        default:
            return String(localized: "Erreur pendant la transcription de la réunion.")
        }
    }
}
