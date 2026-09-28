import Foundation

/// Découpe une durée totale en tranches se chevauchant, pour rester sous la
/// limite de taille d'un provider (25 Mo côté Groq, ADR-0001 C4) sur un
/// enregistrement long — voir ADR-0003 pour la justification des règles
/// ci-dessous, ce fichier les implémente sans les rejustifier.
public enum AudioChunker {
    /// - Parameters:
    ///   - totalDuration: durée totale de l'enregistrement.
    ///   - maxChunkDuration: durée maximale d'un chunk (voir `maxDuration`
    ///     pour la dériver d'une limite de taille et d'un bitrate).
    ///   - overlap: recouvrement entre deux chunks consécutifs, pour ne
    ///     jamais couper un mot ou une phrase pile sur une frontière dure.
    public static func plan(
        totalDuration: TimeInterval,
        maxChunkDuration: TimeInterval,
        overlap: TimeInterval
    ) -> [AudioChunkPlan] {
        guard totalDuration > 0 else { return [] }
        guard totalDuration > maxChunkDuration else {
            return [AudioChunkPlan(start: 0, end: totalDuration)]
        }
        precondition(
            overlap >= 0 && overlap < maxChunkDuration,
            "overlap doit être positif et strictement inférieur à maxChunkDuration"
        )

        let step = maxChunkDuration - overlap
        var chunks: [AudioChunkPlan] = []
        var start: TimeInterval = 0

        while start < totalDuration {
            let tentativeEnd = start + maxChunkDuration
            if tentativeEnd >= totalDuration {
                // Dernier chunk : va jusqu'au bout, quelle que soit sa
                // longueur réelle (peut être plus court que maxChunkDuration).
                chunks.append(AudioChunkPlan(start: start, end: totalDuration))
                break
            }
            if totalDuration - tentativeEnd < overlap {
                // Ce qu'il resterait après ce chunk serait plus court que le
                // recouvrement lui-même — presque aucun contenu réellement
                // nouveau. Absorbé ici plutôt que d'ouvrir un chunk suivant
                // minuscule.
                chunks.append(AudioChunkPlan(start: start, end: totalDuration))
                break
            }
            chunks.append(AudioChunkPlan(start: start, end: tentativeEnd))
            start += step
        }
        return chunks
    }

    /// Dérive une durée de chunk sûre à partir d'une limite de taille de
    /// fichier et du bitrate de l'encodage utilisé.
    ///
    /// - Parameter safetyMargin: l'overhead du conteneur (AAC/MP4, plus le
    ///   multipart HTTP) fait dépasser légèrement le calcul brut
    ///   bitrate × durée — même logique de marge de sécurité que le budget
    ///   mémoire clavier (35-40 Mo visés pour une limite dure de 77 Mo, C2,
    ///   ADR-0001).
    public static func maxDuration(
        forBitrateBitsPerSecond bitrate: Double,
        sizeLimitBytes: Int,
        safetyMargin: Double = 0.9
    ) -> TimeInterval {
        let sizeLimitBits = Double(sizeLimitBytes) * 8
        return (sizeLimitBits / bitrate) * safetyMargin
    }
}
