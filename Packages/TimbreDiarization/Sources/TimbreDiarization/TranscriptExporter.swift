import Foundation

/// Exports structurés d'un transcript — fonctions pures (les libellés de
/// locuteurs sont fournis par l'appelant, voir `TranscriptFormatting` côté
/// app), donc testables sans UI.
public enum TranscriptExporter {
    /// Titre en `#`, puis un paragraphe par tour avec le locuteur en gras.
    /// Si un rapport existe, il précède le transcript, sous deux titres de
    /// niveau 2 (`reportTitle`, `transcriptTitle`, fournis par l'appelant
    /// pour rester localisables).
    public static func markdown(
        turns: [SpeakerTurn],
        labels: [String],
        title: String,
        report: String? = nil,
        reportTitle: String = "Rapport",
        transcriptTitle: String = "Transcript"
    ) -> String {
        let body = zip(labels, turns)
            .map { label, turn in "**\(label)** :\n\(turn.text)" }
            .joined(separator: "\n\n")
        guard let report, !report.isEmpty else {
            return "# \(title)\n\n\(body)\n"
        }
        return "# \(title)\n\n## \(reportTitle)\n\n\(report)\n\n## \(transcriptTitle)\n\n\(body)\n"
    }

    /// `true` si au moins un tour a des horodatages — sinon (réunion
    /// enregistrée avant leur introduction) un SRT n'aurait aucun sens.
    public static func canExportSRT(turns: [SpeakerTurn]) -> Bool {
        turns.contains { $0.start != nil && $0.end != nil }
    }

    /// Sous-titres SRT. Un tour peut durer plusieurs minutes : il est
    /// découpé en repères de `maxWordsPerCue` mots au plus, dont le timing
    /// est réparti proportionnellement au nombre de mots (les mots n'ont
    /// pas d'horodatage individuel conservé dans `SpeakerTurn`). Les tours
    /// sans horodatage sont ignorés.
    public static func srt(turns: [SpeakerTurn], labels: [String], maxWordsPerCue: Int = 12) -> String {
        var cues: [String] = []
        var index = 1
        for (turn, label) in zip(turns, labels) {
            guard let start = turn.start, let end = turn.end, end >= start else { continue }
            let words = turn.text.split(separator: " ")
            guard !words.isEmpty else { continue }

            let chunks = stride(from: 0, to: words.count, by: maxWordsPerCue).map {
                Array(words[$0..<min($0 + maxWordsPerCue, words.count)])
            }
            let duration = end - start
            var consumed = 0
            for (chunkIndex, chunk) in chunks.enumerated() {
                let cueStart = start + duration * Double(consumed) / Double(words.count)
                consumed += chunk.count
                let cueEnd = start + duration * Double(consumed) / Double(words.count)
                let prefix = chunkIndex == 0 ? "\(label) : " : ""
                cues.append(
                    "\(index)\n\(timestamp(cueStart)) --> \(timestamp(cueEnd))\n\(prefix)\(chunk.joined(separator: " "))"
                )
                index += 1
            }
        }
        return cues.joined(separator: "\n\n") + (cues.isEmpty ? "" : "\n")
    }

    static func timestamp(_ seconds: TimeInterval) -> String {
        let totalMilliseconds = Int((max(seconds, 0) * 1000).rounded())
        let hours = totalMilliseconds / 3_600_000
        let minutes = (totalMilliseconds / 60_000) % 60
        let secs = (totalMilliseconds / 1000) % 60
        let millis = totalMilliseconds % 1000
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, secs, millis)
    }
}

extension MeetingRecord {
    /// Recherche insensible à la casse et aux accents, sur le texte, les
    /// noms de locuteurs personnalisés. Requête vide = tout correspond.
    public func matches(searchQuery query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        if turns.contains(where: { $0.text.range(of: trimmed, options: options) != nil }) { return true }
        if report?.text.range(of: trimmed, options: options) != nil { return true }
        return speakerNames.values.contains { $0.range(of: trimmed, options: options) != nil }
    }
}
