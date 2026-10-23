//
//  AudioSessionUsage.swift
//  Timbre
//

import os

/// Compte les enregistreurs qui utilisent `AVAudioSession.sharedInstance()`.
///
/// La session audio est un singleton partagé par toute l'app : la dictée
/// (`DictationController`, qui garde son moteur 30 s après une dictée pour
/// une reprise rapide) et la réunion (`MeetingRecordingController`) ont
/// chacune leur `BackgroundRecorder`, donc leur propre `AVAudioEngine`, mais
/// pas leur propre session. Quand l'un s'arrêtait, il désactivait la session
/// sous les pieds de l'autre — une réunion lancée moins de 30 s après une
/// dictée était coupée à la fin de la fenêtre de grâce. La session n'est
/// désactivée que par le dernier enregistreur actif.
final class AudioSessionUsage: Sendable {
    static let shared = AudioSessionUsage()

    private let count = OSAllocatedUnfairLock<Int>(initialState: 0)

    /// Un enregistreur vient de démarrer son moteur.
    func acquire() {
        count.withLock { $0 += 1 }
    }

    /// Un enregistreur s'arrête. `true` si c'était le dernier : seul lui doit
    /// désactiver la session. Jamais en dessous de zéro (un `stop()` répété
    /// ou sans démarrage préalable ne casse pas le compte).
    func release() -> Bool {
        count.withLock { value in
            value = max(0, value - 1)
            return value == 0
        }
    }

    var activeCount: Int { count.withLock { $0 } }
}
