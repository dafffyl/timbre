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
    let record: MeetingRecord

    var body: some View {
        TranscriptTurnsView(turns: record.turns)
            .navigationTitle(record.recordedAt.formatted(date: .abbreviated, time: .shortened))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !record.turns.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: TranscriptFormatting.plainText(for: record.turns))
                    }
                }
            }
    }
}
