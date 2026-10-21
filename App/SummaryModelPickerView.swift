//
//  SummaryModelPickerView.swift
//  Timbre
//

import SwiftUI
import TimbreTranscription

/// Choix du modèle d'un service : liste récupérée en ligne (`GET /models`)
/// quand une clé est disponible, repli sur les suggestions du préréglage, et
/// saisie libre pour un identifiant que la liste ne montre pas (ADR-0009).
struct SummaryModelPickerView: View {
    let service: SummaryService
    let customBaseURL: String
    let apiKey: String
    @Binding var selection: String

    @State private var models: [String] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var shown: [String] {
        var list = models.isEmpty ? service.suggestedModels : models
        if !selection.isEmpty, !list.contains(selection) { list.insert(selection, at: 0) }
        return list
    }

    var body: some View {
        ZStack {
            AuroraBackground()
            Form {
                Section {
                    TextField("Identifiant du modèle", text: $selection)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text("Colle ici un identifiant exact si le modèle voulu n'est pas dans la liste.")
                }
                .listRowBackground(Color.timbreSurface.opacity(0.55))

                Section {
                    if isLoading {
                        HStack(spacing: 10) {
                            ProgressView().tint(Color.timbreViolet)
                            Text("Chargement des modèles…").foregroundStyle(Color.timbreTextSecondary)
                        }
                    }
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.timbreCaption())
                            .foregroundStyle(Color.timbreDanger)
                    }
                    ForEach(shown, id: \.self) { model in
                        Button {
                            selection = model
                        } label: {
                            HStack {
                                Text(model).foregroundStyle(Color.timbreTextPrimary)
                                Spacer()
                                if model == selection {
                                    Image(systemName: "checkmark").foregroundStyle(Color.timbreViolet)
                                }
                            }
                        }
                    }
                    Button("Actualiser la liste") { Task { await load() } }
                        .foregroundStyle(Color.timbreViolet)
                        .disabled(isLoading)
                } header: {
                    Text(models.isEmpty ? "Suggestions" : "Modèles disponibles")
                } footer: {
                    if apiKey.isEmpty {
                        Text("Saisis d'abord la clé API du service pour récupérer la liste à jour.")
                    }
                }
                .listRowBackground(Color.timbreSurface.opacity(0.55))
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Modèle")
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
        .task { if !apiKey.isEmpty { await load() } }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let baseURL = service.defaultBaseURL ?? SummaryService.validatedBaseURL(customBaseURL) else {
            errorMessage = MeetingReportController.message(for: SummaryError.invalidEndpoint, service: service)
            return
        }
        let key = apiKey
        let lister = ChatModelLister(style: service.apiStyle, baseURL: baseURL, apiKey: { key })
        do {
            models = try await lister.listModels()
        } catch {
            errorMessage = MeetingReportController.message(for: error, service: service)
        }
    }
}
