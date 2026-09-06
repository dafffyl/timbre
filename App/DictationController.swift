//
//  DictationController.swift
//  Timbre
//

import Foundation
import AVFoundation
import TimbreCore
import TimbreSecurity
import TimbreTranscription

/// Point d'entrée unique du cycle de dictée côté app — accessible aussi bien
/// depuis `ContentView` (ouverture via `openURL`, cas "froid") que depuis le
/// handler de notification Darwin de `AppDelegate` (reprise "à chaud", sans
/// jamais passer par l'UI). D'où le singleton : il n'y a jamais qu'une seule
/// dictée active à la fois, et `AppDelegate` n'a pas de hiérarchie de vues
/// pour atteindre une instance qui vivrait dans `ContentView`.
@MainActor
@Observable
final class DictationController {
    static let shared = DictationController()

    enum State: Equatable {
        case idle
        case recording
        case transcribing
        case done
        case failed(String)
    }

    private(set) var state: State = .idle

    /// Filet de sécurité : au-delà, l'app termine et transcrit d'elle-même,
    /// même sans signal du clavier.
    private static let maxRecordingDuration: TimeInterval = 180

    /// Durée pendant laquelle le moteur reste actif après une dictée, pour
    /// permettre une reprise immédiate sans bascule visible si la suivante
    /// arrive vite derrière (cf. comportement observé chez Wispr Flow :
    /// bascule seulement au tout premier essai, plus jamais ensuite tant
    /// qu'on enchaîne). Valeur choisie à vue de nez, pas calibrée
    /// précisément — un délai trop court retombe juste sur `openURL`
    /// (dégradation gracieuse), un délai trop long coûte un peu de
    /// batterie pour rien : le risque est faible des deux côtés.
    private static let graceWindow: TimeInterval = 30

    private let channel = DictationChannel()
    private let recorder = BackgroundRecorder()
    private var pollTimer: Timer?
    private var graceTimer: Timer?
    private var recordingStartedAt: Date?

    private init() {}

    // MARK: - Démarrage

    /// Appelé depuis `ContentView` quand l'app est ouverte via
    /// `timbre://dictate` — cas "froid" (première dictée, ou fenêtre de
    /// grâce déjà expirée).
    func startFromColdWake() {
        guard let initialRequest = channel.read(), initialRequest.status == .pending else { return }
        beginRecording(requestID: initialRequest.id, resuming: false)
    }

    /// Appelé uniquement depuis le handler de notification Darwin
    /// (`AppDelegate`), jamais depuis l'UI. Ne fait rien hors fenêtre de
    /// grâce — le clavier retombe alors sur `openURL` de lui-même après son
    /// propre délai (voir `DictationViewModel.coldWakeURLIfStillPending`).
    func handleWakeSignal() {
        guard graceTimer != nil, recorder.isEngineRunning else { return }
        guard let request = channel.read(), request.status == .pending else { return }
        graceTimer?.invalidate()
        graceTimer = nil
        beginRecording(requestID: request.id, resuming: true)
    }

    private func beginRecording(requestID: UUID, resuming: Bool) {
        if resuming {
            do {
                try recorder.resumeRecording()
            } catch {
                markFailed(requestID: requestID, message: "Impossible de reprendre l'enregistrement.")
                return
            }
            claimAndStartPolling(requestID: requestID)
            return
        }

        Task { @MainActor in
            let allowed = await requestMicrophonePermission()
            guard allowed else {
                markFailed(requestID: requestID, message: "Accès micro refusé — active-le dans Réglages.")
                return
            }
            do {
                try recorder.start()
            } catch {
                markFailed(requestID: requestID, message: "Impossible de démarrer l'enregistrement.")
                return
            }
            claimAndStartPolling(requestID: requestID)
        }
    }

    private func claimAndStartPolling(requestID: UUID) {
        guard var request = channel.read(), request.id == requestID else {
            recorder.stop()
            return
        }
        request.status = .recording
        request.statusUpdatedAt = Date()
        channel.write(request)
        state = .recording
        recordingStartedAt = Date()
        startPolling(requestID: requestID)
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }


    // MARK: - Pendant l'enregistrement

    /// Rythme de 0,1s : lit `stopRequested`/le filet de sécurité de durée,
    /// ET pousse le niveau audio courant pour l'onde live du clavier.
    /// Toujours découplé du tap audio lui-même (voir `BackgroundRecorder`).
    private func startPolling(requestID: UUID) {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pollDuringRecording(requestID: requestID)
            }
        }
    }

    private func pollDuringRecording(requestID: UUID) {
        guard var request = channel.read(), request.id == requestID else {
            // Le clavier a vidé le canal (`cancel()`) ou une autre requête
            // l'a remplacé : on interprète ça comme une annulation.
            cancelRecording()
            return
        }

        if request.stopRequested {
            stopRecordingAndTranscribe(requestID: requestID)
            return
        }

        if let startedAt = recordingStartedAt,
            Date().timeIntervalSince(startedAt) > Self.maxRecordingDuration
        {
            stopRecordingAndTranscribe(requestID: requestID)
            return
        }

        request.audioLevel = recorder.currentLevel
        channel.write(request)
    }

    private func cancelRecording() {
        pollTimer?.invalidate()
        pollTimer = nil
        recordingStartedAt = nil
        if let url = recorder.recordedURL {
            try? FileManager.default.removeItem(at: url)
        }
        state = .idle
        beginGrace()
    }

    private func stopRecordingAndTranscribe(requestID: UUID) {
        pollTimer?.invalidate()
        pollTimer = nil
        recordingStartedAt = nil

        guard let url = recorder.recordedURL, var request = channel.read(), request.id == requestID else {
            beginGrace()
            return
        }

        request.status = .transcribing
        request.statusUpdatedAt = Date()
        channel.write(request)
        state = .transcribing
        beginGrace()

        Task { @MainActor in
            do {
                let audioData = try Data(contentsOf: url)
                try? FileManager.default.removeItem(at: url)

                let apiKeyStore = APIKeyStore()
                let provider = GroqProvider(apiKey: { (try? apiKeyStore.load()) ?? nil })
                let result = try await provider.transcribe(TranscriptionRequest(audio: audioData, language: "fr"))

                guard var ready = channel.read(), ready.id == requestID else { return }
                ready.status = .ready
                ready.statusUpdatedAt = Date()
                ready.resultText = result.text
                channel.write(ready)
                state = .done
            } catch {
                markFailed(requestID: requestID, message: Self.userMessage(for: error))
            }
        }
    }

    // MARK: - Fenêtre de grâce

    /// Laisse le moteur tourner à vide (sans écrire sur disque) pendant
    /// `graceWindow` — permet à `handleWakeSignal` de reprendre sans jamais
    /// rouvrir l'app si une nouvelle dictée arrive assez vite.
    private func beginGrace() {
        recorder.beginGracePeriod()
        graceTimer?.invalidate()
        graceTimer = Timer.scheduledTimer(withTimeInterval: Self.graceWindow, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.endGrace()
            }
        }
    }

    private func endGrace() {
        graceTimer = nil
        recorder.stop()
    }

    private func markFailed(requestID: UUID, message: String) {
        if var request = channel.read(), request.id == requestID {
            request.status = .failed
            request.statusUpdatedAt = Date()
            request.errorMessage = message
            channel.write(request)
        }
        state = .failed(message)
        beginGrace()
    }

    private static func userMessage(for error: Error) -> String {
        guard let error = error as? TranscriptionError else {
            return "Erreur inattendue."
        }
        switch error {
        case .missingAPIKey:
            return "Clé API Groq manquante — configure-la dans les réglages."
        case .fileTooLarge:
            return "Enregistrement trop long pour Groq (25 Mo max)."
        case .network:
            return "Problème réseau — vérifie ta connexion."
        case .rateLimited:
            return "Trop de requêtes envoyées à Groq — réessaie dans un instant."
        case .server(let statusCode, _):
            return "Erreur Groq (code \(statusCode))."
        case .decoding, .invalidResponse:
            return "Réponse inattendue de Groq."
        case .cancelled:
            return "Annulé."
        }
    }
}
