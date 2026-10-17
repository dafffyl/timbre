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
            VoiceStore().deleteMeetingVoices(meetingID: visible[index].id)
        }
        records = DiarizationEnvironment.historyStore.loadAll()
    }
}

struct MeetingHistoryDetailView: View {
    enum Tab: Hashable {
        case transcript, report
    }

    @State private var record: MeetingRecord
    @State private var renamingSpeaker: SpeakerID?
    @State private var newName = ""
    @State private var tab: Tab = .transcript
    @State private var reportController = MeetingReportController()
    @State private var instructions = SummaryPreferences.instructions
    @State private var copiedReport = false

    /// `true` pour un transcript tout juste produit : génère le rapport
    /// d'office si l'utilisateur l'a demandé dans les réglages.
    private let autoGenerate: Bool

    init(record: MeetingRecord, autoGenerate: Bool = false) {
        _record = State(initialValue: record)
        self.autoGenerate = autoGenerate
        _instructions = State(initialValue: record.report?.instructions ?? SummaryPreferences.instructions)
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            VStack(spacing: 0) {
                if !record.turns.isEmpty {
                    Picker("Affichage", selection: $tab) {
                        Text("Transcript").tag(Tab.transcript)
                        Text("Rapport").tag(Tab.report)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                switch tab {
                case .transcript:
                    TranscriptTurnsView(
                        turns: record.turns,
                        names: record.speakerNames,
                        onTapSpeaker: { speaker in
                            renamingSpeaker = speaker
                            newName = record.speakerNames[speaker.rawValue] ?? ""
                        }
                    )
                case .report:
                    reportContent
                }
            }
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
        .task {
            if autoGenerate, SummaryPreferences.autoGenerate, record.report == nil, !record.turns.isEmpty {
                tab = .report
                await generateReport()
            }
        }
    }

    // MARK: - Rapport

    private var reportContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                switch reportController.state {
                case .generating:
                    HStack(spacing: 12) {
                        ProgressView().tint(Color.timbreViolet)
                        Text("Rédaction du rapport…")
                            .font(.timbreBody(15))
                            .foregroundStyle(Color.timbreTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.timbreCaption())
                        .foregroundStyle(Color.timbreDanger)
                case .idle:
                    EmptyView()
                }

                if let report = record.report {
                    MarkdownReportText(markdown: report.text)
                        .timbreCard()
                    Text("Généré le \(report.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.timbreCaption())
                        .foregroundStyle(Color.timbreTextSecondary)
                    HStack(spacing: 12) {
                        Button(copiedReport ? "Copié" : "Copier") {
                            UIPasteboard.general.string = report.text
                            copiedReport = true
                        }
                        .buttonStyle(TimbreSecondaryButtonStyle())
                    }
                } else if reportController.state != .generating {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pas encore de rapport")
                            .font(.timbreTitle(16))
                            .foregroundStyle(Color.timbreTextPrimary)
                        Text("Le texte du transcript est envoyé à Groq (même clé que la transcription) pour rédiger un compte rendu selon tes instructions.")
                            .font(.timbreCaption())
                            .foregroundStyle(Color.timbreTextSecondary)
                    }
                    .timbreCard()
                }

                instructionsEditor

                Button(record.report == nil ? "Générer le rapport" : "Régénérer le rapport") {
                    Task { await generateReport() }
                }
                .buttonStyle(TimbrePrimaryButtonStyle())
                .disabled(reportController.state == .generating)
            }
            .padding(20)
        }
    }

    private var instructionsEditor: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $instructions)
                    .font(.timbreBody(14))
                    .frame(minHeight: 140)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                HStack {
                    Button("Rétablir par défaut") {
                        instructions = SummaryPreferences.defaultInstructions
                    }
                    Spacer()
                    Button("Enregistrer comme réglage") {
                        SummaryPreferences.instructions = instructions
                    }
                }
                .font(.timbreCaption())
                .foregroundStyle(Color.timbreViolet)
            }
            .padding(.top, 8)
        } label: {
            Text("Instructions pour ce rapport")
                .font(.timbreLabel(15))
                .foregroundStyle(Color.timbreTextPrimary)
        }
        .tint(Color.timbreViolet)
    }

    private func generateReport() async {
        if let updated = await reportController.generate(for: record, instructions: instructions) {
            record = updated
            copiedReport = false
        }
    }

    // MARK: - Export

    private var exportMenu: some View {
        let labels = TranscriptFormatting.displayLabels(for: record.turns, names: record.speakerNames)
        let title = String(localized: "Réunion du \(record.recordedAt.formatted(date: .long, time: .shortened))")
        let baseName = "Timbre-" + record.recordedAt.formatted(.iso8601.year().month().day())
        return Menu {
            ShareLink(item: TranscriptFormatting.plainText(for: record.turns, names: record.speakerNames)) {
                Label("Transcript (texte)", systemImage: "text.alignleft")
            }
            ShareLink(
                item: TranscriptExportFile.markdown(
                    contents: TranscriptExporter.markdown(
                        turns: record.turns, labels: labels, title: title,
                        report: record.report?.text,
                        reportTitle: String(localized: "Rapport"), transcriptTitle: String(localized: "Transcript")),
                    baseName: baseName),
                preview: SharePreview("\(baseName).md")
            ) {
                Label(record.report == nil ? "Markdown (.md)" : "Rapport + transcript (.md)", systemImage: "doc.richtext")
            }
            if let report = record.report {
                ShareLink(item: report.text) {
                    Label("Rapport seul (texte)", systemImage: "doc.text")
                }
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
        if !trimmed.isEmpty {
            VoiceRecognitionService(store: VoiceStore()).learn(name: trimmed, meetingID: record.id, speaker: speaker)
        }
        renamingSpeaker = nil
    }
}
