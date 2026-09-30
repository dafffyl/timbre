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
                TranscriptTurnsView(turns: turns)
            }
        }
        .navigationTitle("Transcript")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if case .done(let turns) = controller.state, !turns.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: TranscriptFormatting.plainText(for: turns))
                }
            }
        }
        .task {
            await controller.run(audioURL: audioURL)
            // Le fichier audio n'est plus utile une fois le pipeline terminé
            // (succès ou échec) — seul le texte du transcript est conservé
            // (voir MeetingRecord), jamais l'audio (ADR-0005).
            try? FileManager.default.removeItem(at: audioURL)

            if case .done(let turns) = controller.state, !turns.isEmpty {
                DiarizationEnvironment.historyStore.save(MeetingRecord(turns: turns))
            }
        }
    }
}
