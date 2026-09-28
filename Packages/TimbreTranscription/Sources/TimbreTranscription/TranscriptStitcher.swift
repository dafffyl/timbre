import Foundation

/// Le résultat de transcription d'un seul chunk, avec le plan qui l'a
/// produit — nécessaire pour recaler ses horodatages de mots (locaux au
/// chunk) sur la timeline globale de l'enregistrement.
public struct TranscribedChunk: Sendable, Equatable {
    public let plan: AudioChunkPlan
    public let words: [TranscriptionWord]

    public init(plan: AudioChunkPlan, words: [TranscriptionWord]) {
        self.plan = plan
        self.words = words
    }
}

/// Recolle les transcriptions indépendantes de chunks qui se chevauchent en
/// une seule liste de mots sur la timeline globale — voir ADR-0003 pour la
/// justification de la stratégie (coupure au milieu de la zone de
/// recouvrement) et ses limites assumées.
///
/// Suppose que tous les chunks ont un résultat (pas de gestion d'échec de
/// transcription partiel ici — décision de la couche d'orchestration, pas
/// de ce module pur).
public enum TranscriptStitcher {
    public static func stitch(_ chunks: [TranscribedChunk]) -> [TranscriptionWord] {
        guard !chunks.isEmpty else { return [] }

        // Chaque horodatage de mot est local au chunk qui l'a produit —
        // premier passage obligatoire avant toute comparaison entre chunks.
        let globalChunks = chunks.map { chunk in
            chunk.words.map { word in
                TranscriptionWord(
                    text: word.text,
                    start: word.start + chunk.plan.start,
                    end: word.end + chunk.plan.start
                )
            }
        }

        guard globalChunks.count > 1 else { return globalChunks[0] }

        var stitched: [TranscriptionWord] = []
        for index in globalChunks.indices {
            let words = globalChunks[index]
            let previousPlan = index > 0 ? chunks[index - 1].plan : nil
            let nextPlan = index < chunks.count - 1 ? chunks[index + 1].plan : nil

            let lowerBound = previousPlan.map { cutover(betweenEndOf: $0, andStartOf: chunks[index].plan) }
            let upperBound = nextPlan.map { cutover(betweenEndOf: chunks[index].plan, andStartOf: $0) }

            let kept = words.filter { word in
                if let lowerBound, word.start < lowerBound { return false }
                if let upperBound, word.start >= upperBound { return false }
                return true
            }
            stitched.append(contentsOf: kept)
        }
        return stitched
    }

    /// Milieu de la zone de recouvrement entre deux chunks consécutifs, en
    /// temps global — calculé à partir des plans réels plutôt que supposé
    /// égal au paramètre `overlap` d'origine, plus robuste si le dernier
    /// chunk a une durée irrégulière (cas limite du "reste absorbé",
    /// `AudioChunker.plan`).
    private static func cutover(betweenEndOf earlier: AudioChunkPlan, andStartOf later: AudioChunkPlan) -> TimeInterval {
        let overlapStart = max(earlier.start, later.start)
        let overlapEnd = min(earlier.end, later.end)
        guard overlapEnd > overlapStart else {
            // Pas de vrai recouvrement entre ces deux plans (ne devrait pas
            // arriver avec une sortie d'`AudioChunker.plan`, mais reste
            // défini plutôt que de produire un résultat absurde si jamais
            // des plans construits à la main se touchent sans se chevaucher).
            return later.start
        }
        return (overlapStart + overlapEnd) / 2
    }
}
