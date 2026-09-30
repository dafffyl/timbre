//
//  TranscriptRendering.swift
//  Timbre
//

import SwiftUI
import TimbreDiarization

/// Rendu partagé d'un transcript — utilisé par `MeetingHistoryDetailView`,
/// que ce soit pour un résultat frais du pipeline ou une réunion de
/// l'historique, pour ne jamais avoir deux implémentations de l'étiquetage
/// des locuteurs qui pourraient diverger.
///
/// `onTapSpeaker` : `nil` en lecture seule, une closure quand le renommage
/// est possible (l'étiquette devient alors un bouton avec une icône crayon).
struct TranscriptTurnsView: View {
    let turns: [SpeakerTurn]
    var names: [String: String] = [:]
    var onTapSpeaker: ((SpeakerID) -> Void)?

    var body: some View {
        if turns.isEmpty {
            Text("Aucune parole détectée.")
                .foregroundStyle(.secondary)
        } else {
            let labels = TranscriptFormatting.displayLabels(for: turns, names: names)
            List(Array(turns.enumerated()), id: \.offset) { index, turn in
                VStack(alignment: .leading, spacing: 4) {
                    speakerLabel(for: turn, label: labels[index])
                    Text(turn.text)
                }
            }
        }
    }

    @ViewBuilder
    private func speakerLabel(for turn: SpeakerTurn, label: String) -> some View {
        if let speaker = turn.speaker, let onTapSpeaker {
            Button {
                onTapSpeaker(speaker)
            } label: {
                HStack(spacing: 4) {
                    Text(label)
                    Image(systemName: "pencil")
                        .font(.caption2)
                }
            }
            .buttonStyle(.plain)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
        } else {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
        }
    }
}

enum TranscriptFormatting {
    /// Le nom personnalisé (`names`) prime sur "Locuteur N" quand il existe
    /// et n'est pas vide — sinon repli sur la position de première
    /// apparition, plus lisible que les identifiants bruts de FluidAudio
    /// ("S1", "S2"). Purement de l'affichage, ne touche pas `SpeakerID`
    /// lui-même.
    static func displayLabels(for turns: [SpeakerTurn], names: [String: String] = [:]) -> [String] {
        var order: [SpeakerID] = []
        for turn in turns {
            if let speaker = turn.speaker, !order.contains(speaker) {
                order.append(speaker)
            }
        }
        return turns.map { turn in
            guard let speaker = turn.speaker else { return "Non identifié" }
            if let customName = names[speaker.rawValue], !customName.isEmpty {
                return customName
            }
            guard let index = order.firstIndex(of: speaker) else { return "Non identifié" }
            return "Locuteur \(index + 1)"
        }
    }

    /// Format d'export : texte brut, un tour par paragraphe — lisible tel
    /// quel collé dans n'importe quelle app (Notes, Mail…), pas de format
    /// structuré (Markdown, JSON) tant que rien ne le demande.
    static func plainText(for turns: [SpeakerTurn], names: [String: String] = [:]) -> String {
        let labels = displayLabels(for: turns, names: names)
        return zip(labels, turns)
            .map { label, turn in "\(label) :\n\(turn.text)" }
            .joined(separator: "\n\n")
    }
}
