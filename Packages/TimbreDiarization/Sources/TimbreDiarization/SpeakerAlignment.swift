import Foundation
import TimbreTranscription

/// Attribue chaque mot transcrit au locuteur dont le segment de diarisation
/// le recouvre le plus dans le temps. Voir ADR-0003 pour la justification
/// de chaque règle ci-dessous et le catalogue de cas limites — ce fichier
/// implémente ces décisions, il ne les justifie pas à nouveau en commentaire.
public enum SpeakerAlignment {
    public static func align(
        words: [TranscriptionWord],
        segments: [SpeakerSegment],
        gapTolerance: TimeInterval = 1.0
    ) -> [AttributedWord] {
        let sortedSegments = segments.sorted { $0.start < $1.start }
        var attributed: [AttributedWord] = []
        attributed.reserveCapacity(words.count)

        var previousSpeaker: SpeakerID?
        for word in words {
            let speaker = bestSpeaker(
                for: word,
                in: sortedSegments,
                gapTolerance: gapTolerance,
                previousSpeaker: previousSpeaker
            )
            attributed.append(AttributedWord(word: word, speaker: speaker))
            if let speaker {
                previousSpeaker = speaker
            }
        }
        return attributed
    }

    private static func bestSpeaker(
        for word: TranscriptionWord,
        in sortedSegments: [SpeakerSegment],
        gapTolerance: TimeInterval,
        previousSpeaker: SpeakerID?
    ) -> SpeakerID? {
        // Mot de durée nulle ou négative (cas limite 6, ADR-0003) : la
        // formule de recouvrement classique donne toujours 0 pour un
        // intervalle de largeur nulle, même pile au milieu d'un segment —
        // on teste la contenance d'un point plutôt qu'un chevauchement. Si
        // aucun segment ne contient le point, on retombe sur la même
        // logique de plus-proche-voisin-avec-tolérance que le cas général
        // (`nearestSegment` gère un point comme un intervalle de largeur
        // nulle sans traitement spécial).
        guard word.end > word.start else {
            let containing = sortedSegments.filter { $0.start <= word.start && word.start < $0.end }
            if !containing.isEmpty {
                return pickAmongTies(containing, previousSpeaker: previousSpeaker)
            }
            return nearestSegment(to: word, in: sortedSegments, tolerance: gapTolerance)?.speaker
        }

        var bestOverlap: TimeInterval = 0
        var bestSegments: [SpeakerSegment] = []
        for segment in sortedSegments {
            let overlap = overlapDuration(wordStart: word.start, wordEnd: word.end, segment: segment)
            guard overlap > 0 else { continue }
            if overlap > bestOverlap {
                bestOverlap = overlap
                bestSegments = [segment]
            } else if overlap == bestOverlap {
                bestSegments.append(segment)
            }
        }

        if !bestSegments.isEmpty {
            return pickAmongTies(bestSegments, previousSpeaker: previousSpeaker)
        }

        // Aucun recouvrement positif : mot dans un trou entre deux segments
        // (cas limite 3, ADR-0003) — on cherche le plus proche, mais
        // seulement dans une tolérance courte, pour ne jamais deviner à la
        // place d'une vraie parole manquée (C4, ADR-0001).
        return nearestSegment(to: word, in: sortedSegments, tolerance: gapTolerance)?.speaker
    }

    private static func overlapDuration(wordStart: TimeInterval, wordEnd: TimeInterval, segment: SpeakerSegment) -> TimeInterval {
        let start = max(wordStart, segment.start)
        let end = min(wordEnd, segment.end)
        return max(0, end - start)
    }

    /// Égalité entre plusieurs segments (cas limite 5, ADR-0003) : continuité
    /// avec le locuteur précédent si possible, sinon le segment le plus tôt
    /// — un repli déterministe plutôt qu'un choix arbitraire dépendant de
    /// l'ordre de tri.
    private static func pickAmongTies(_ candidates: [SpeakerSegment], previousSpeaker: SpeakerID?) -> SpeakerID? {
        guard !candidates.isEmpty else { return nil }
        if let previousSpeaker, candidates.contains(where: { $0.speaker == previousSpeaker }) {
            return previousSpeaker
        }
        return candidates.min(by: { $0.start < $1.start })?.speaker
    }

    private static func nearestSegment(to word: TranscriptionWord, in sortedSegments: [SpeakerSegment], tolerance: TimeInterval) -> SpeakerSegment? {
        var closest: SpeakerSegment?
        var closestDistance = TimeInterval.infinity

        for segment in sortedSegments {
            let distance: TimeInterval
            if word.end <= segment.start {
                distance = segment.start - word.end
            } else if word.start >= segment.end {
                distance = word.start - segment.end
            } else {
                distance = 0
            }
            if distance < closestDistance {
                closestDistance = distance
                closest = segment
            }
        }

        guard closestDistance <= tolerance else { return nil }
        return closest
    }
}
