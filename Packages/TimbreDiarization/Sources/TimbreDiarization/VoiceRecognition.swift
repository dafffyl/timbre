import Foundation

/// Empreinte d'un locuteur dans UNE réunion : moyenne des embeddings de ses
/// segments, pondérée par leur durée, normalisée (norme 1). `seconds` est la
/// durée de parole cumulée, utile pour pondérer la fusion dans un profil.
public struct SpeakerVoice: Sendable, Equatable, Codable {
    public let embedding: [Float]
    public let seconds: TimeInterval

    public init(embedding: [Float], seconds: TimeInterval) {
        self.embedding = embedding
        self.seconds = seconds
    }
}

/// Résultat complet d'une diarisation : segments + empreinte de chaque
/// locuteur. `speakerVoices` est vide pour un moteur qui n'expose pas
/// d'embeddings.
public struct DiarizationOutput: Sendable, Equatable {
    public let segments: [SpeakerSegment]
    public let speakerVoices: [SpeakerID: SpeakerVoice]

    public init(segments: [SpeakerSegment], speakerVoices: [SpeakerID: SpeakerVoice] = [:]) {
        self.segments = segments
        self.speakerVoices = speakerVoices
    }
}

extension DiarizationProvider {
    /// Repli : les moteurs sans embeddings n'ont pas à implémenter cette
    /// méthode, la reconnaissance des voix est alors simplement indisponible.
    public func diarizeDetailed(_ audioURL: URL) async throws -> DiarizationOutput {
        DiarizationOutput(segments: try await diarize(audioURL))
    }
}

/// Voix connue : empreinte persistée d'une personne nommée par l'utilisateur.
/// Donnée **biométrique** (RGPD, art. 9) : voir ADR-0007 — locale à
/// l'appareil, jamais envoyée, supprimable, activée par consentement.
public struct VoiceProfile: Sendable, Equatable, Codable, Identifiable {
    public let id: UUID
    public var name: String
    public private(set) var embedding: [Float]
    /// Durée de parole ayant servi à construire l'empreinte — plus elle est
    /// grande, moins une nouvelle réunion déplace le profil.
    public private(set) var totalSeconds: TimeInterval
    public let createdAt: Date
    public private(set) var updatedAt: Date

    public init(
        id: UUID = UUID(), name: String, voice: SpeakerVoice,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.embedding = VoiceMath.normalized(voice.embedding)
        self.totalSeconds = voice.seconds
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    /// Fusionne une nouvelle observation (moyenne pondérée par la durée de
    /// parole, plafonnée pour qu'un vieux profil reste capable d'évoluer).
    public mutating func merge(_ voice: SpeakerVoice, now: Date = Date()) {
        guard voice.embedding.count == embedding.count, voice.seconds > 0 else { return }
        let oldWeight = min(totalSeconds, Self.maxWeightSeconds)
        let combined = zip(embedding, VoiceMath.normalized(voice.embedding))
            .map { Float(oldWeight) * $0 + Float(voice.seconds) * $1 }
        embedding = VoiceMath.normalized(combined)
        totalSeconds += voice.seconds
        updatedAt = now
    }

    /// 10 minutes de parole : au-delà, une nouvelle réunion pèse toujours
    /// au moins `seconds / (seconds + 600)`.
    static let maxWeightSeconds: TimeInterval = 600
}

public enum VoiceMath {
    public static func normalized(_ vector: [Float]) -> [Float] {
        let norm = vector.reduce(0) { $0 + $1 * $1 }.squareRoot()
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }

    /// Similarité cosinus ; 0 si les dimensions diffèrent ou un vecteur est nul.
    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for index in a.indices {
            dot += a[index] * b[index]
            na += a[index] * a[index]
            nb += b[index] * b[index]
        }
        guard na > 0, nb > 0 else { return 0 }
        return dot / (na.squareRoot() * nb.squareRoot())
    }

    /// Moyenne pondérée normalisée d'embeddings de même dimension.
    public static func weightedMean(_ items: [(embedding: [Float], weight: Float)]) -> [Float]? {
        guard let first = items.first, !first.embedding.isEmpty else { return nil }
        var sum = [Float](repeating: 0, count: first.embedding.count)
        for item in items where item.embedding.count == sum.count && item.weight > 0 {
            let unit = normalized(item.embedding)
            for index in sum.indices { sum[index] += unit[index] * item.weight }
        }
        guard sum.contains(where: { $0 != 0 }) else { return nil }
        return normalized(sum)
    }
}

public struct SpeakerMatch: Sendable, Equatable {
    public let profileID: UUID
    public let name: String
    public let similarity: Float
}

/// Associe les locuteurs d'une réunion aux voix connues.
///
/// Prudent par construction : un locuteur n'est nommé que si (1) la
/// similarité dépasse `threshold`, (2) il est nettement plus proche de son
/// meilleur profil que du suivant (`margin`), et (3) chaque profil n'est
/// attribué qu'à un seul locuteur (le plus proche). Mieux vaut laisser
/// « Locuteur N » qu'attribuer le mauvais nom.
///
/// Les seuils par défaut sont des **valeurs initiales non calibrées** sur un
/// jeu de voix réelles : à ajuster à l'usage.
public enum SpeakerMatcher {
    public static let defaultThreshold: Float = 0.65
    public static let defaultMargin: Float = 0.05

    public static func match(
        voices: [SpeakerID: SpeakerVoice],
        profiles: [VoiceProfile],
        threshold: Float = defaultThreshold,
        margin: Float = defaultMargin
    ) -> [SpeakerID: SpeakerMatch] {
        guard !profiles.isEmpty else { return [:] }

        struct Candidate {
            let speaker: SpeakerID
            let profile: VoiceProfile
            let similarity: Float
        }

        var candidates: [Candidate] = []
        for (speaker, voice) in voices {
            let scored = profiles
                .map { Candidate(speaker: speaker, profile: $0, similarity: VoiceMath.cosine(voice.embedding, $0.embedding)) }
                .sorted { $0.similarity > $1.similarity }
            guard let best = scored.first, best.similarity >= threshold else { continue }
            if scored.count > 1, best.similarity - scored[1].similarity < margin { continue }
            candidates.append(best)
        }

        var result: [SpeakerID: SpeakerMatch] = [:]
        var usedProfiles: Set<UUID> = []
        for candidate in candidates.sorted(by: { $0.similarity > $1.similarity })
        where !usedProfiles.contains(candidate.profile.id) {
            usedProfiles.insert(candidate.profile.id)
            result[candidate.speaker] = SpeakerMatch(
                profileID: candidate.profile.id, name: candidate.profile.name, similarity: candidate.similarity)
        }
        return result
    }
}
