//
//  MeetingHistoryView.swift
//  Timbre
//

import SwiftUI
import TimbreDiarization

/// `NavigationStack` propre (comme `DiarizationSetupView`) pour fonctionner
/// correctement présenté en `.sheet` depuis `ContentView`.
struct MeetingHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var records: [MeetingRecord] = DiarizationEnvironment.historyStore.loadAll()
    @State private var searchText = ""

    private var filteredRecords: [MeetingRecord] {
        records.filter { $0.matches(searchQuery: searchText) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()

                if records.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.timbreTextSecondary)
                        Text("Aucune réunion transcrite pour l'instant.")
                            .font(.timbreBody(15))
                            .foregroundStyle(Color.timbreTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                } else {
                    List {
                        ForEach(filteredRecords) { record in
                            NavigationLink {
                                MeetingHistoryDetailView(record: record)
                            } label: {
                                row(for: record)
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                        .onDelete(perform: delete)
                        if filteredRecords.isEmpty {
                            Text("Aucun résultat pour « \(searchText) ».")
                                .font(.timbreBody(15))
                                .foregroundStyle(Color.timbreTextSecondary)
                                .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Réunions")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Rechercher dans les transcripts")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func row(for record: MeetingRecord) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(LinearGradient.timbreAccent.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(LinearGradient.timbreAccent)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(record.recordedAt, format: .dateTime.day().month().year().hour().minute())
                    .font(.timbreTitle(15))
                    .foregroundStyle(Color.timbreTextPrimary)
                Text(preview(for: record))
                    .font(.timbreCaption())
                    .foregroundStyle(Color.timbreTextSecondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(14)
        .timbreCard(padding: 0)
    }

    private func preview(for record: MeetingRecord) -> String {
        record.turns.first?.text ?? "Transcript vide"
    }

    private func delete(at offsets: IndexSet) {
        let visible = filteredRecords
        for index in offsets {
            DiarizationEnvironment.historyStore.delete(id: visible[index].id)
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
        ZStack {
            AuroraBackground()
            TranscriptTurnsView(
                turns: record.turns,
                names: record.speakerNames,
                onTapSpeaker: { speaker in
                    renamingSpeaker = speaker
                    newName = record.speakerNames[speaker.rawValue] ?? ""
                }
            )
        }
        .preferredColorScheme(.dark)
        .navigationTitle(record.recordedAt.formatted(date: .abbreviated, time: .shortened))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !record.turns.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    exportMenu
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

    private var exportMenu: some View {
        let labels = TranscriptFormatting.displayLabels(for: record.turns, names: record.speakerNames)
        let title = "Réunion du " + record.recordedAt.formatted(date: .long, time: .shortened)
        let baseName = "Timbre-" + record.recordedAt.formatted(.iso8601.year().month().day())
        return Menu {
            ShareLink(item: TranscriptFormatting.plainText(for: record.turns, names: record.speakerNames)) {
                Label("Texte", systemImage: "text.alignleft")
            }
            ShareLink(
                item: TranscriptExportFile.markdown(
                    contents: TranscriptExporter.markdown(turns: record.turns, labels: labels, title: title),
                    baseName: baseName),
                preview: SharePreview("\(baseName).md")
            ) {
                Label("Markdown (.md)", systemImage: "doc.richtext")
            }
            if TranscriptExporter.canExportSRT(turns: record.turns) {
                ShareLink(
                    item: TranscriptExportFile.srt(
                        contents: TranscriptExporter.srt(turns: record.turns, labels: labels),
                        baseName: baseName),
                    preview: SharePreview("\(baseName).srt")
                ) {
                    Label("Sous-titres (.srt)", systemImage: "captions.bubble")
                }
            }
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .accessibilityLabel("Exporter")
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
