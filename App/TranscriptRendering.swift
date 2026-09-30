//
//  TranscriptRendering.swift
//  Timbre
//

import SwiftUI
import TimbreDiarization

/// Rendu partagé d'un transcript — utilisé par `MeetingTranscriptView`
/// (résultat frais du pipeline) et l'historique (`MeetingHistoryDetailView`),
/// pour ne jamais avoir deux implémentations de l'étiquetage des locuteurs
/// qui pourraient diverger.
struct TranscriptTurnsView: View {
    let turns: [SpeakerTurn]

    var body: some View {
        if turns.isEmpty {
            Text("Aucune parole détectée.")
                .foregroundStyle(.secondary)
        } else {
            let labels = TranscriptFormatting.displayLabels(for: turns)
            List(Array(turns.enumerated()), id: \.offset) { index, turn in
                VStack(alignment: .leading, spacing: 4) {
                    Text(labels[index])
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(turn.text)
                }
            }
        }
    }
}

enum TranscriptFormatting {
    /// "Locuteur 1", "Locuteur 2"… dans l'ordre de première apparition —
    /// plus lisible que les identifiants bruts de FluidAudio ("S1", "S2"),
    /// et correspond au vocabulaire du produit (voir README). Purement de
    /// l'affichage, ne touche pas `SpeakerID` lui-même.
    static func displayLabels(for turns: [SpeakerTurn]) -> [String] {
        var order: [SpeakerID] = []
        for turn in turns {
            if let speaker = turn.speaker, !order.contains(speaker) {
                order.append(speaker)
            }
        }
        return turns.map { turn in
            guard let speaker = turn.speaker, let index = order.firstIndex(of: speaker) else {
                return "Non identifié"
            }
            return "Locuteur \(index + 1)"
        }
    }

    /// Format d'export : texte brut, un tour par paragraphe — lisible tel
    /// quel collé dans n'importe quelle app (Notes, Mail…), pas de format
    /// structuré (Markdown, JSON) tant que rien ne le demande.
    static func plainText(for turns: [SpeakerTurn]) -> String {
        let labels = displayLabels(for: turns)
        return zip(labels, turns)
            .map { label, turn in "\(label) :\n\(turn.text)" }
            .joined(separator: "\n\n")
    }
}
