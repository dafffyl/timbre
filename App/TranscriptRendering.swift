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
/// Une carte par tour de parole, avec une pastille colorée par locuteur
/// (violet/corail en alternance selon l'ordre de première apparition —
/// mêmes deux couleurs que l'icône, pas une palette arbitraire) : visualise
/// directement ce que "timbre" désigne, pas juste une liste de texte.
///
/// `onTapSpeaker` : `nil` en lecture seule, une closure quand le renommage
/// est possible (la pastille devient alors un bouton avec une icône crayon).
struct TranscriptTurnsView: View {
    let turns: [SpeakerTurn]
    var names: [String: String] = [:]
    var onTapSpeaker: ((SpeakerID) -> Void)?

    var body: some View {
        if turns.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "waveform.slash")
                    .font(.system(size: 36))
                    .foregroundStyle(Color.timbreTextSecondary)
                Text("Aucune parole détectée.")
                    .font(.timbreBody(15))
                    .foregroundStyle(Color.timbreTextSecondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let order = TranscriptFormatting.speakerOrder(in: turns)
            let labels = TranscriptFormatting.displayLabels(for: turns, names: names)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(turns.enumerated()), id: \.offset) { index, turn in
                        turnCard(
                            turn: turn,
                            label: labels[index],
                            colorIndex: turn.speaker.flatMap { order.firstIndex(of: $0) }
                        )
                    }
                }
                .padding(20)
            }
        }
    }

    @ViewBuilder
    private func turnCard(turn: SpeakerTurn, label: String, colorIndex: Int?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            speakerBadge(for: turn, label: label, colorIndex: colorIndex)
            Text(turn.text)
                .font(.timbreBody(16))
                .foregroundStyle(Color.timbreTextPrimary)
        }
        .timbreCard()
    }

    @ViewBuilder
    private func speakerBadge(for turn: SpeakerTurn, label: String, colorIndex: Int?) -> some View {
        let color = TranscriptFormatting.accentColor(forIndex: colorIndex)
        Group {
            if let speaker = turn.speaker, let onTapSpeaker {
                Button {
                    onTapSpeaker(speaker)
                } label: {
                    HStack(spacing: 5) {
                        Text(label)
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
            } else {
                Text(label)
            }
        }
        .font(.timbreCaption(12))
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.16))
        .clipShape(Capsule())
    }
}

enum TranscriptFormatting {
    /// Locuteurs dans l'ordre de leur première apparition — base commune à
    /// `displayLabels` (numérotation) et à la couleur d'accent de
    /// `TranscriptTurnsView` (même ordre pour les deux, jamais divergent).
    static func speakerOrder(in turns: [SpeakerTurn]) -> [SpeakerID] {
        var order: [SpeakerID] = []
        for turn in turns {
            if let speaker = turn.speaker, !order.contains(speaker) {
                order.append(speaker)
            }
        }
        return order
    }

    /// Violet/corail en alternance — les deux couleurs de l'icône, jamais
    /// une troisième teinte arbitraire même au-delà de deux locuteurs.
    static func accentColor(forIndex index: Int?) -> Color {
        guard let index else { return .timbreTextSecondary }
        return index.isMultiple(of: 2) ? .timbreViolet : .timbreCoral
    }

    /// Le nom personnalisé (`names`) prime sur "Locuteur N" quand il existe
    /// et n'est pas vide — sinon repli sur la position de première
    /// apparition, plus lisible que les identifiants bruts de FluidAudio
    /// ("S1", "S2"). Purement de l'affichage, ne touche pas `SpeakerID`
    /// lui-même.
    static func displayLabels(for turns: [SpeakerTurn], names: [String: String] = [:]) -> [String] {
        let order = speakerOrder(in: turns)
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
