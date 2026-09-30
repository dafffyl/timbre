import Foundation

/// Interface commune à tout moteur de diarisation — même schéma que
/// `TranscriptionProvider`/`TextCleanupProvider` dans `TimbreTranscription`.
///
/// `prepareModels()` séparée de `diarize` : le chargement/téléchargement des
/// modèles (coûteux, voir ADR-0004) doit être déclenché explicitement par
/// l'appelant, qui contrôle QUAND ce coût est payé — jamais implicitement au
/// milieu d'une diarisation.
public protocol DiarizationProvider: Sendable {
    func prepareModels() async throws
    func diarize(_ audioURL: URL) async throws -> [SpeakerSegment]
}
