//
//  MeetingTranscriptView.swift
//  Timbre
//

import SwiftUI
import TimbreDiarization

/// Écran fonctionnel avant tout (ADR-0005), pas encore la refonte visuelle
/// prévue plus tard. Lance le pipeline complet (diarisation + chunking +
/// transcription + alignement, voir `MeetingTranscriptionController`) dès
/// l'apparition, sur le fichier reçu de `MeetingRecordingView`.
struct MeetingTranscriptView: View {
    let audioURL: URL

    @State private var controller = MeetingTranscriptionController()

    var body: some View {
        Group {
            switch controller.state {
            case .idle, .diarizing:
                ProgressView("Analyse des locuteurs…")

            case .transcribing(let chunk, let total):
                ProgressView("Transcription (\(chunk)/\(total))…")

            case .aligning:
                ProgressView("Assemblage du transcript…")

            case .failed(let message):
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.largeTitle)
                    Text(message)
                        .multilineTextAlignment(.center)
                }
                .padding()

            case .done(let turns):
                transcriptList(turns)
            }
        }
        .navigationTitle("Transcript")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if case .done(let turns) = controller.state, !turns.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: Self.plainText(for: turns))
                }
            }
        }
        .task {
            await controller.run(audioURL: audioURL)
            // Le fichier n'est plus utile une fois le pipeline terminé (succès
            // ou échec) — l'utilisateur ne revient jamais en arrière dessus,
            // pas d'historique dans cet incrément (ADR-0005).
            try? FileManager.default.removeItem(at: audioURL)
        }
    }

    @ViewBuilder
    private func transcriptList(_ turns: [SpeakerTurn]) -> some View {
        if turns.isEmpty {
            Text("Aucune parole détectée.")
                .foregroundStyle(.secondary)
        } else {
            let labels = Self.displayLabels(for: turns)
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

    /// "Locuteur 1", "Locuteur 2"… dans l'ordre de première apparition —
    /// plus lisible que les identifiants bruts de FluidAudio ("S1", "S2"),
    /// et correspond au vocabulaire du produit (voir README). Purement de
    /// l'affichage, ne touche pas `SpeakerID` lui-même.
    private static func displayLabels(for turns: [SpeakerTurn]) -> [String] {
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
    /// structuré (Markdown, JSON) tant que rien ne le demande. Réutilise
    /// `displayLabels` pour rester cohérent avec ce qui est affiché à
    /// l'écran.
    private static func plainText(for turns: [SpeakerTurn]) -> String {
        let labels = displayLabels(for: turns)
        return zip(labels, turns)
            .map { label, turn in "\(label) :\n\(turn.text)" }
            .joined(separator: "\n\n")
    }
}
