/// Identifiant opaque de locuteur — même schéma que `ProviderIdentifier`
/// dans `TimbreTranscription` (pas d'`enum` fermé : le nombre de locuteurs
/// n'est connu qu'à l'exécution, propre à chaque réunion). La correspondance
/// avec un libellé humain ("Locuteur 1", "Locuteur 2"…) est un problème
/// d'affichage, pas de ce type : il porte l'identifiant brut renvoyé par le
/// moteur de diarisation, rien de plus.
public struct SpeakerID: Sendable, Hashable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
