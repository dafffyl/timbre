import TimbreTranscription

/// Résultat de `SpeakerAlignment.align` : un mot transcrit et le locuteur
/// auquel il a été attribué. `speaker == nil` — mot non attribuable (voir
/// ADR-0003, cas limite du "trou" entre deux segments) — n'est pas une
/// erreur, c'est un résultat légitime que l'appelant doit savoir afficher
/// (ex. "[non identifié]") plutôt que de supposer une attribution partout.
public struct AttributedWord: Sendable, Equatable {
    public let word: TranscriptionWord
    public let speaker: SpeakerID?

    public init(word: TranscriptionWord, speaker: SpeakerID?) {
        self.word = word
        self.speaker = speaker
    }
}
