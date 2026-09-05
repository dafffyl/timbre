import Foundation

/// Un mot horodaté — la matière première de l'alignement diarisation
/// (Phase 5+) : recouvrement temporel entre un mot et un segment locuteur.
public struct TranscriptionWord: Sendable, Equatable {
    public let text: String
    public let start: TimeInterval
    public let end: TimeInterval

    public init(text: String, start: TimeInterval, end: TimeInterval) {
        self.text = text
        self.start = start
        self.end = end
    }
}

/// `words` est vide pour un provider sans granularité mot (capacité
/// annoncée via `ProviderCapabilities.wordTimestamps`) — l'appelant ne doit
/// jamais supposer sa présence sans vérifier la capacité au préalable.
public struct TranscriptionResult: Sendable, Equatable {
    public let text: String
    public let words: [TranscriptionWord]

    public init(text: String, words: [TranscriptionWord] = []) {
        self.text = text
        self.words = words
    }
}
