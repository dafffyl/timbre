/// Regroupe une suite de mots attribués (déjà triée chronologiquement par
/// construction de `SpeakerAlignment.align`) en tours de parole — voir
/// ADR-0005. Une suite de mots non attribués (`speaker == nil`) forme son
/// propre tour comme un autre, jamais rattachée arbitrairement au tour
/// voisin.
public enum TranscriptFormatter {
    public static func groupIntoTurns(_ words: [AttributedWord]) -> [SpeakerTurn] {
        guard let first = words.first else { return [] }

        var turns: [SpeakerTurn] = []
        var currentSpeaker = first.speaker
        var currentWords: [String] = []

        for word in words {
            if word.speaker != currentSpeaker {
                turns.append(SpeakerTurn(speaker: currentSpeaker, text: currentWords.joined(separator: " ")))
                currentSpeaker = word.speaker
                currentWords = []
            }
            currentWords.append(word.word.text)
        }
        turns.append(SpeakerTurn(speaker: currentSpeaker, text: currentWords.joined(separator: " ")))

        return turns
    }
}
