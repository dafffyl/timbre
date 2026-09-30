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
///
/// Une fois terminé (`.done`), affiche directement `MeetingHistoryDetailView`
/// plutôt qu'un rendu séparé — un seul endroit qui sait afficher/renommer un
/// transcript, que ce soit frais ou tiré de l'historique.
struct MeetingTranscriptView: View {
    let audioURL: URL

    @State private var controller = MeetingTranscriptionController()
    @State private var savedRecord: MeetingRecord?
    @State private var hadMissingChunks = false

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

            case .done:
                if let savedRecord {
                    VStack(spacing: 0) {
                        // Ponctuel, pas persisté : le marqueur
                        // "[transcription indisponible]" reste de toute
                        // façon visible en clair dans le transcript lui-même
                        // (ADR-0005), cet avertissement n'est qu'un signal
                        // immédiat en plus.
                        if hadMissingChunks {
                            Label(
                                "Certains passages n'ont pas pu être transcrits (réseau).",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.footnote)
                            .foregroundStyle(.orange)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(Color.orange.opacity(0.15))
                        }
                        MeetingHistoryDetailView(record: savedRecord)
                    }
                }
            }
        }
        .navigationTitle("Transcript")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await controller.run(audioURL: audioURL)
            // Le fichier audio n'est plus utile une fois le pipeline terminé
            // (succès ou échec) — seul le texte du transcript est conservé
            // (voir MeetingRecord), jamais l'audio (ADR-0005).
            try? FileManager.default.removeItem(at: audioURL)

            if case .done(let turns, let missingChunks) = controller.state {
                let record = MeetingRecord(turns: turns)
                if !turns.isEmpty {
                    DiarizationEnvironment.historyStore.save(record)
                }
                hadMissingChunks = missingChunks
                savedRecord = record
            }
        }
    }
}
