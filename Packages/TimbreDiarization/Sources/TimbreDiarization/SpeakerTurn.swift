import Foundation

/// Une suite maximale de mots consécutifs partageant le même locuteur (ou
/// tous non attribués, `speaker == nil`) — l'unité d'affichage d'un
/// transcript de réunion ("Locuteur 1: ...").
///
/// `start`/`end` (secondes depuis le début de l'enregistrement) sont
/// optionnels : les réunions enregistrées avant leur introduction n'en ont
/// pas (le décodage JSON les lit comme `nil`), et sans eux l'export de
/// sous-titres est indisponible.
public struct SpeakerTurn: Sendable, Equatable, Codable {
    public let speaker: SpeakerID?
    public let text: String
    public let start: TimeInterval?
    public let end: TimeInterval?

    public init(speaker: SpeakerID?, text: String, start: TimeInterval? = nil, end: TimeInterval? = nil) {
        self.speaker = speaker
        self.text = text
        self.start = start
        self.end = end
    }
}
