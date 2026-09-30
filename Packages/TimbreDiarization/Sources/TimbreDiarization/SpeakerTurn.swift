/// Une suite maximale de mots consécutifs partageant le même locuteur (ou
/// tous non attribués, `speaker == nil`) — l'unité d'affichage d'un
/// transcript de réunion ("Locuteur 1: ...").
public struct SpeakerTurn: Sendable, Equatable, Codable {
    public let speaker: SpeakerID?
    public let text: String

    public init(speaker: SpeakerID?, text: String) {
        self.speaker = speaker
        self.text = text
    }
}
