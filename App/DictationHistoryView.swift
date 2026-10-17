//
//  DictationHistoryView.swift
//  Timbre
//

import SwiftUI

/// Dictées récentes (texte local) et dictées échouées à réessayer. Même
/// structure que `MeetingHistoryView` : `NavigationStack` propre pour
/// fonctionner présentée en `.sheet`.
struct DictationHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var records = DictationHistoryStore().loadAll()
    @State private var pending = PendingDictationStore.all()
    @State private var retryingID: UUID?
    @State private var retryError: String?
    @State private var copiedID: UUID?
    @State private var searchText = ""

    private var filteredRecords: [DictationRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return records }
        return records.filter {
            $0.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()

                if records.isEmpty && pending.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 36))
                            .foregroundStyle(Color.timbreTextSecondary)
                            .accessibilityHidden(true)
                        Text(DictationPreferences.keepHistory
                            ? String(localized: "Aucune dictée pour l'instant.")
                            : String(localized: "L'historique des dictées est désactivé dans les réglages."))
                            .font(.timbreBody(15))
                            .foregroundStyle(Color.timbreTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(32)
                } else {
                    List {
                        if !pending.isEmpty {
                            Section("À réessayer") {
                                ForEach(pending) { item in
                                    pendingRow(item)
                                }
                            }
                            .listRowBackground(Color.timbreSurface.opacity(0.55))
                        }
                        if let retryError {
                            Text(retryError)
                                .font(.timbreCaption())
                                .foregroundStyle(Color.timbreDanger)
                                .listRowBackground(Color.clear)
                        }
                        Section("Récentes") {
                            ForEach(filteredRecords) { record in
                                recordRow(record)
                            }
                            .onDelete { offsets in
                                let visible = filteredRecords
                                for index in offsets {
                                    DictationHistoryStore().delete(id: visible[index].id)
                                }
                                records = DictationHistoryStore().loadAll()
                            }
                        }
                        .listRowBackground(Color.timbreSurface.opacity(0.55))
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Dictées")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Rechercher une dictée")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
                if !records.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Tout effacer", role: .destructive) {
                            DictationHistoryStore().deleteAll()
                            records = []
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func recordRow(_ record: DictationRecord) -> some View {
        Button {
            UIPasteboard.general.string = record.text
            copiedID = record.id
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(record.text)
                    .font(.timbreBody(15))
                    .foregroundStyle(Color.timbreTextPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
                Text(copiedID == record.id ? String(localized: "Copié") : record.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.timbreCaption())
                    .foregroundStyle(copiedID == record.id ? Color.timbreViolet : Color.timbreTextSecondary)
            }
        }
        .accessibilityHint("Copie le texte")
    }

    private func pendingRow(_ item: PendingDictation) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Dictée non transcrite")
                    .font(.timbreBody(15))
                    .foregroundStyle(Color.timbreTextPrimary)
                Text(item.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.timbreCaption())
                    .foregroundStyle(Color.timbreTextSecondary)
            }
            Spacer()
            if retryingID == item.id {
                ProgressView().tint(Color.timbreViolet)
            } else {
                Button("Réessayer") { retry(item) }
                    .foregroundStyle(Color.timbreViolet)
            }
        }
    }

    private func retry(_ item: PendingDictation) {
        retryingID = item.id
        retryError = nil
        Task {
            do {
                _ = try await DictationController.shared.retry(item)
            } catch {
                retryError = DictationController.message(for: error)
            }
            retryingID = nil
            pending = PendingDictationStore.all()
            records = DictationHistoryStore().loadAll()
        }
    }
}
