//
//  MeetingHistoryView.swift
//  Timbre
//

import SwiftUI
import TimbreDiarization

/// Écran fonctionnel avant tout (ADR-0005/pas de refonte visuelle encore).
/// `NavigationStack` propre (comme `DiarizationSetupView`) pour fonctionner
/// correctement présenté en `.sheet` depuis `ContentView`.
struct MeetingHistoryView: View {
    @State private var records: [MeetingRecord] = DiarizationEnvironment.historyStore.loadAll()

    var body: some View {
        NavigationStack {
            Group {
                if records.isEmpty {
                    Text("Aucune réunion transcrite pour l'instant.")
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(records) { record in
                            NavigationLink {
                                MeetingHistoryDetailView(record: record)
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.recordedAt, format: .dateTime.day().month().year().hour().minute())
                                        .font(.subheadline.bold())
                                    Text(preview(for: record))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Réunions")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func preview(for record: MeetingRecord) -> String {
        record.turns.first?.text ?? "Transcript vide"
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            DiarizationEnvironment.historyStore.delete(id: records[index].id)
        }
        records = DiarizationEnvironment.historyStore.loadAll()
    }
}

struct MeetingHistoryDetailView: View {
    @State private var record: MeetingRecord
    @State private var renamingSpeaker: SpeakerID?
    @State private var newName = ""

    init(record: MeetingRecord) {
        _record = State(initialValue: record)
    }

    var body: some View {
        TranscriptTurnsView(
            turns: record.turns,
            names: record.speakerNames,
            onTapSpeaker: { speaker in
                renamingSpeaker = speaker
                newName = record.speakerNames[speaker.rawValue] ?? ""
            }
        )
        .navigationTitle(record.recordedAt.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !record.turns.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: TranscriptFormatting.plainText(for: record.turns, names: record.speakerNames))
                }
            }
        }
        .alert(
            "Renommer le locuteur",
            isPresented: Binding(
                get: { renamingSpeaker != nil },
                set: { isPresented in if !isPresented { renamingSpeaker = nil } }
            )
        ) {
            TextField("Nom", text: $newName)
            Button("Enregistrer") { saveRename() }
            Button("Annuler", role: .cancel) { renamingSpeaker = nil }
        }
    }

    /// Vide le nom personnalisé (retombe sur "Locuteur N") plutôt que
    /// d'enregistrer une chaîne vide qui s'afficherait littéralement comme
    /// nom — `displayLabels` traite déjà "vide" comme "pas de nom
    /// personnalisé" (`TranscriptRendering.swift`), cohérent des deux côtés.
    private func saveRename() {
        guard let speaker = renamingSpeaker else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        record.speakerNames[speaker.rawValue] = trimmed.isEmpty ? nil : trimmed
        DiarizationEnvironment.historyStore.update(record)
        renamingSpeaker = nil
    }
}
