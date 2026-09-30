//
//  MeetingTranscriptView.swift
//  Timbre
//

import SwiftUI
import TimbreDiarization

/// Lance le pipeline complet (diarisation + chunking + transcription +
/// alignement, voir `MeetingTranscriptionController`) dès l'apparition, sur
/// le fichier reçu de `MeetingRecordingView`.
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
        ZStack {
            AuroraBackground()

            switch controller.state {
            case .idle, .diarizing:
                progress("Analyse des locuteurs…")

            case .transcribing(let chunk, let total):
                progress("Transcription (\(chunk)/\(total))…")

            case .aligning:
                progress("Assemblage du transcript…")

            case .failed(let message):
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.timbreDanger.opacity(0.16))
                            .frame(width: 88, height: 88)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(Color.timbreDanger)
                    }
                    Text(message)
                        .font(.timbreBody(15))
                        .foregroundStyle(Color.timbreTextSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)

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
                            .font(.timbreCaption())
                            .foregroundStyle(Color.timbreCoral)
                            .padding(10)
                            .frame(maxWidth: .infinity)
                            .background(Color.timbreCoral.opacity(0.14))
                        }
                        MeetingHistoryDetailView(record: savedRecord)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
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

    private func progress(_ label: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(Color.timbreViolet)
                .scaleEffect(1.3)
            Text(label)
                .font(.timbreBody(15))
                .foregroundStyle(Color.timbreTextSecondary)
        }
    }
}
