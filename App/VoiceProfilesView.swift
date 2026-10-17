//
//  VoiceProfilesView.swift
//  Timbre
//

import SwiftUI
import TimbreDiarization

/// Voix connues : liste, renommage, suppression individuelle ou totale.
/// Tout reste sur l'appareil (ADR-0007).
struct VoiceProfilesView: View {
    @State private var profiles = VoiceStore().profiles()
    @State private var renaming: VoiceProfile?
    @State private var newName = ""
    @State private var confirmDeleteAll = false

    var body: some View {
        ZStack {
            AuroraBackground()
            List {
                if profiles.isEmpty {
                    Text("Aucune voix connue. Nomme un locuteur dans le transcript d'une réunion (avec la reconnaissance activée) pour qu'il soit reconnu la prochaine fois.")
                        .font(.timbreBody(15))
                        .foregroundStyle(Color.timbreTextSecondary)
                        .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(profiles) { profile in
                            Button {
                                renaming = profile
                                newName = profile.name
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(profile.name)
                                        .font(.timbreBody(16))
                                        .foregroundStyle(Color.timbreTextPrimary)
                                    Text("\(Int(profile.totalSeconds / 60)) min de parole · mis à jour \(profile.updatedAt.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.timbreCaption())
                                        .foregroundStyle(Color.timbreTextSecondary)
                                }
                            }
                            .accessibilityHint("Renommer")
                        }
                        .onDelete { offsets in
                            for index in offsets { VoiceStore().deleteProfile(id: profiles[index].id) }
                            profiles = VoiceStore().profiles()
                        }
                    } footer: {
                        Text("Une empreinte est une suite de nombres calculée à partir de la voix, stockée uniquement sur cet iPhone. Glisse vers la gauche pour oublier une voix.")
                    }
                    .listRowBackground(Color.timbreSurface.opacity(0.55))

                    Section {
                        Button("Supprimer toutes les empreintes vocales", role: .destructive) {
                            confirmDeleteAll = true
                        }
                    }
                    .listRowBackground(Color.timbreSurface.opacity(0.55))
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Voix connues")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .alert("Renommer la voix", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Nom", text: $newName)
            Button("Enregistrer") {
                if let renaming { VoiceStore().renameProfile(id: renaming.id, to: newName) }
                profiles = VoiceStore().profiles()
                renaming = nil
            }
            Button("Annuler", role: .cancel) { renaming = nil }
        }
        .confirmationDialog(
            "Supprimer toutes les empreintes vocales ?", isPresented: $confirmDeleteAll, titleVisibility: .visible
        ) {
            Button("Tout supprimer", role: .destructive) {
                VoiceStore().deleteEverything()
                profiles = []
            }
        } message: {
            Text("Les voix connues et les empreintes de toutes les réunions seront effacées. Les noms déjà donnés dans les transcripts restent.")
        }
    }
}
