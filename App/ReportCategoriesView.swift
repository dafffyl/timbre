//
//  ReportCategoriesView.swift
//  Timbre
//

import SwiftUI
import TimbreTranscription

/// Gère les catégories de rapport : créer, modifier, supprimer (ADR-0009).
struct ReportCategoriesView: View {
    private let store = ReportCategoryStore.shared
    @State private var categories = ReportCategoryStore.shared.categories

    var body: some View {
        ZStack {
            AuroraBackground()
            List {
                Section {
                    ForEach(categories) { category in
                        NavigationLink {
                            ReportCategoryEditor(category: category) { saved in
                                store.update(saved)
                                categories = store.categories
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(category.name).foregroundStyle(Color.timbreTextPrimary)
                                Text(ReportCategory.formatName(category.format))
                                    .font(.timbreCaption())
                                    .foregroundStyle(Color.timbreTextSecondary)
                            }
                        }
                    }
                    .onDelete(perform: delete)
                } footer: {
                    Text("Une catégorie combine un format (compte rendu structuré, résumé court, libre) et tes instructions. Tu la choisis au moment de générer le rapport.")
                }
                .listRowBackground(Color.timbreSurface.opacity(0.55))
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Catégories de rapport")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.update(ReportCategory(name: String(localized: "Nouvelle catégorie"), format: .free))
                    categories = store.categories
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Ajouter une catégorie")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { store.delete(id: categories[index].id) }
        categories = store.categories
    }
}

struct ReportCategoryEditor: View {
    @State private var category: ReportCategory
    let onSave: (ReportCategory) -> Void

    init(category: ReportCategory, onSave: @escaping (ReportCategory) -> Void) {
        _category = State(initialValue: category)
        self.onSave = onSave
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            Form {
                Section {
                    TextField("Nom", text: $category.name)
                    Picker("Format", selection: $category.format) {
                        ForEach(ReportFormat.allCases, id: \.self) { format in
                            Text(ReportCategory.formatName(format)).tag(format)
                        }
                    }
                } footer: {
                    Text("Le format fixe la forme du rapport ; les instructions ci-dessous ajoutent ton contexte (ton, sections, public visé…).")
                }
                .listRowBackground(Color.timbreSurface.opacity(0.55))

                Section {
                    TextEditor(text: $category.instructions)
                        .frame(minHeight: 160)
                } header: {
                    Text("Instructions")
                } footer: {
                    Text("Ex. « Réunion client : note les engagements pris et les objections. » Laisse vide pour n'utiliser que le format.")
                }
                .listRowBackground(Color.timbreSurface.opacity(0.55))
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle(category.name)
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        // Enregistre en quittant l'écran : pas de bouton à oublier.
        .onDisappear {
            var saved = category
            let trimmed = saved.name.trimmingCharacters(in: .whitespacesAndNewlines)
            saved.name = trimmed.isEmpty ? String(localized: "Sans nom") : trimmed
            onSave(saved)
        }
    }
}
