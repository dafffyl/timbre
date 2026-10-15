//
//  MeetingRecordingController.swift
//  Timbre
//

import Foundation
import AVFoundation

/// Enregistrement d'une réunion — distinct de `DictationController` (flux
/// différent : pas de clavier, pas d'App Group, une seule longue session
/// plutôt que des allers-retours courts) mais réutilise `BackgroundRecorder`
/// tel quel (voir ADR-0005 : son filet de sécurité de durée vit dans le
/// contrôleur, pas dans la classe elle-même, donc une seconde instance
/// dédiée fonctionne sans aucune modification).
@MainActor
@Observable
final class MeetingRecordingController {
    enum State: Equatable {
        case idle
        case recording
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var elapsed: TimeInterval = 0
    private(set) var audioLevel: Float = 0

    /// Non-`nil` quand une coupure audio système (appel, Siri...) a forcé
    /// l'arrêt sans reprise possible (voir `BackgroundRecorder`) — la vue
    /// l'observe pour basculer automatiquement vers la transcription du
    /// fichier déjà enregistré plutôt que de perdre la réunion.
    private(set) var autoStoppedURL: URL?

    /// 4h, pas 180s comme la dictée (`DictationController`) : le risque à
    /// couvrir ici n'est pas une dictée qui déraille mais un oubli d'arrêter
    /// l'enregistrement d'une vraie réunion.
    private static let maxRecordingDuration: TimeInterval = 4 * 60 * 60

    private let recorder = BackgroundRecorder()
    private var pollTimer: Timer?
    private var startedAt: Date?

    func start() async {
        let allowed = await requestMicrophonePermission()
        guard allowed else {
            state = .failed("Accès micro refusé — active-le dans Réglages.")
            return
        }
        do {
            try recorder.start()
        } catch {
            state = .failed("Impossible de démarrer l'enregistrement.")
            return
        }
        recorder.onUnrecoverableInterruption = { [weak self] in
            self?.handleUnrecoverableInterruption()
        }
        startedAt = Date()
        elapsed = 0
        state = .recording
        startPolling()
    }

    private func handleUnrecoverableInterruption() {
        guard state == .recording else { return }
        autoStoppedURL = stop()
    }

    /// Retourne l'URL du fichier enregistré, ou `nil` si rien n'a été
    /// enregistré (arrêt sans avoir démarré, ou déjà arrêté). L'appelant est
    /// responsable du fichier après cet appel (le passer au pipeline de
    /// transcription, puis le supprimer).
    @discardableResult
    func stop() -> URL? {
        pollTimer?.invalidate()
        pollTimer = nil
        let url = recorder.recordedURL
        recorder.stop()
        state = .idle
        return url
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard let startedAt else { return }
        elapsed = Date().timeIntervalSince(startedAt)
        audioLevel = recorder.currentLevel
        if elapsed > Self.maxRecordingDuration {
            _ = stop()
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
