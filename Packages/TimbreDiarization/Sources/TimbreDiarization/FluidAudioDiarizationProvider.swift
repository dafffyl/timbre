import Foundation
import FluidAudio

/// FluidAudio ne marque pas `OfflineDiarizerManager` `Sendable`, alors que
/// ses méthodes (`prepareModels`/`process`) sont `@concurrent` — elles
/// s'exécutent sur l'executor concurrent global, pas sur l'isolation de
/// l'appelant. Le compilateur ne peut donc pas prouver tout seul que c'est
/// sûr de le partager entre isolations. Ça l'est ici : `FluidAudioDiarizationProvider`
/// ci-dessous est un `actor`, qui sérialise déjà tous les appels à `manager`
/// (jamais deux appels en vol en même temps sur la même instance), et chaque
/// appel est entièrement awaité avant de rendre la main — ce point d'entrée
/// unique ne peut pas produire d'accès concurrent réel.
extension OfflineDiarizerManager: @unchecked @retroactive Sendable {}

/// Wrapper autour de FluidAudio (`OfflineDiarizerManager`, pipeline
/// "Pyannote Community-1") — voir ADR-0004 pour les chiffres mesurés
/// (téléchargement au premier usage, poids du cache, temps à froid/à chaud)
/// qui justifient de ne jamais appeler `prepareModels()` sans passer par
/// `ModelProvisioningCoordinator`.
///
/// `actor` : `OfflineDiarizerManager` est mutable en interne (état des
/// modèles chargés) et ce wrapper ne fait aucune hypothèse sur sa
/// thread-safety propre — sérialiser tous les appels ici est le choix par
/// défaut sûr, au prix d'un enregistrement/diarisation à la fois (largement
/// suffisant : une seule réunion traitée à la fois a du sens).
public actor FluidAudioDiarizationProvider: DiarizationProvider {
    private let manager: OfflineDiarizerManager

    public init(config: OfflineDiarizerConfig = OfflineDiarizerConfig()) {
        self.manager = OfflineDiarizerManager(config: config)
    }

    public func prepareModels() async throws {
        try await manager.prepareModels()
    }

    public func diarize(_ audioURL: URL) async throws -> [SpeakerSegment] {
        let result = try await manager.process(audioURL)
        return result.segments.map {
            // FluidAudio expose des `Float`, `SpeakerSegment` des `TimeInterval`
            // (`Double`, cohérent avec `TranscriptionWord`) — conversion
            // explicite plutôt qu'un changement de type de `SpeakerSegment`
            // pour un détail propre à ce seul provider.
            SpeakerSegment(
                speaker: SpeakerID(rawValue: $0.speakerId),
                start: TimeInterval($0.startTimeSeconds),
                end: TimeInterval($0.endTimeSeconds)
            )
        }
    }
}
