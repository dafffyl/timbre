import Foundation

/// Une tranche de temps à extraire et transcrire indépendamment — voir
/// `AudioChunker.plan`. `start`/`end` sont dans le référentiel de
/// l'enregistrement complet, pas du chunk lui-même.
public struct AudioChunkPlan: Sendable, Equatable {
    public let start: TimeInterval
    public let end: TimeInterval

    public init(start: TimeInterval, end: TimeInterval) {
        self.start = start
        self.end = end
    }
}
