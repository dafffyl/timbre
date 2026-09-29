/// Interface commune à tous les moteurs de nettoyage de texte transcrit
/// (hésitations, ponctuation, reformulation légère) — même logique que
/// `TranscriptionProvider` : l'app ne doit dépendre que de ce protocole,
/// jamais d'une implémentation concrète.
///
/// Volontairement sans `identifier`/`capabilities` (contrairement à
/// `TranscriptionProvider`) : une seule implémentation existe pour l'instant
/// et rien n'exploite encore un choix multi-provider pour cette étape —
/// ajouter ces champs maintenant serait de la généralité non utilisée.
public protocol TextCleanupProvider: Sendable {
    func cleanUp(_ request: TextCleanupRequest) async throws -> TextCleanupResult
}
