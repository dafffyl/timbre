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
        var currentStart = first.word.start
        var currentEnd = first.word.end

        func closeTurn() {
            turns.append(
                SpeakerTurn(
                    speaker: currentSpeaker,
                    text: currentWords.joined(separator: " "),
                    start: currentStart,
                    end: currentEnd
                )
            )
        }

        for word in words {
            if word.speaker != currentSpeaker {
                closeTurn()
                currentSpeaker = word.speaker
                currentWords = []
                currentStart = word.word.start
            }
            currentWords.append(word.word.text)
            currentEnd = word.word.end
        }
        closeTurn()

        return turns
    }
}
