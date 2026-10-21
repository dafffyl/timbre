import SwiftUI
import TimbreSecurity
import TimbreTranscription

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var vocabulary: String = ""
    @State private var cleanupEnabled = false
    @State private var keepHistory = true
    @State private var summaryService = SummaryPreferences.service
    @State private var summaryModel = SummaryPreferences.model
    @State private var summaryKey = ""
    @State private var summaryCustomURL = SummaryPreferences.customBaseURL
    @State private var summaryAuto = SummaryPreferences.autoGenerate
    @State private var savedConfirmation = false
    @State private var language = DictationPreferences.language
    @State private var saveFailed = false

    private let store = APIKeyStore()

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()

                Form {
                    Section {
                        SecureField("Clé API Groq", text: $apiKey)
                            // Pas de `.textContentType(.password)` : iOS
                            // proposerait d'enregistrer la clé dans le
                            // Trousseau iCloud, contraire à l'invariant
                            // « clé Groq locale uniquement » (CLAUDE.md).
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    } header: {
                        Text("Groq")
                    } footer: {
                        Text("Stockée dans le Trousseau, jamais dans les réglages de l'app ni dans les journaux.")
                    }
                    .listRowBackground(Color.timbreSurface.opacity(0.55))

                    Section {
                        Picker("Langue", selection: $language) {
                            ForEach(DictationPreferences.supportedLanguages, id: \.code) { entry in
                                Text(entry.name).tag(entry.code)
                            }
                        }
                    } header: {
                        Text("Langue de transcription")
                    } footer: {
                        Text("S'applique aux dictées et aux réunions. La détection automatique est moins fiable sur les phrases courtes.")
                    }
                    .listRowBackground(Color.timbreSurface.opacity(0.55))

                    Section {
                        TextField("Ex. Kubernetes, Aymeric, Groq…", text: $vocabulary, axis: .vertical)
                            .lineLimit(3...6)
                    } header: {
                        Text("Vocabulaire personnalisé")
                    } footer: {
                        Text("Noms propres ou jargon technique fréquents — améliore leur reconnaissance par Whisper.")
                    }
                    .listRowBackground(Color.timbreSurface.opacity(0.55))

                    Section {
                        Toggle("Nettoyer automatiquement le texte", isOn: $cleanupEnabled)
                            .tint(Color.timbreViolet)
                    } footer: {
                        Text("Retire les hésitations et corrige la ponctuation via un second appel IA, après la transcription. Expérimental : désactivé par défaut.")
                    }
                    .listRowBackground(Color.timbreSurface.opacity(0.55))

                    Section {
                        Picker("Service", selection: $summaryService) {
                            ForEach(SummaryService.allCases, id: \.self) { service in
                                Text(service.displayName).tag(service)
                            }
                        }
                        if summaryService == .groq {
                            Text("Utilise la clé Groq saisie plus haut.")
                                .font(.timbreCaption())
                                .foregroundStyle(Color.timbreTextSecondary)
                        } else {
                            SecureField("Clé API \(summaryService.displayName)", text: $summaryKey)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        if summaryService == .custom {
                            TextField("https://…/v1", text: $summaryCustomURL)
                                .keyboardType(.URL)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }
                        NavigationLink {
                            SummaryModelPickerView(
                                service: summaryService,
                                customBaseURL: summaryCustomURL,
                                apiKey: summaryService == .groq ? apiKey : summaryKey,
                                selection: $summaryModel)
                        } label: {
                            HStack {
                                Text("Modèle")
                                Spacer()
                                Text(summaryModel.isEmpty ? String(localized: "À choisir") : summaryModel)
                                    .foregroundStyle(summaryModel.isEmpty ? Color.timbreCoral : Color.timbreTextSecondary)
                                    .lineLimit(1)
                            }
                        }
                        NavigationLink("Catégories de rapport") { ReportCategoriesView() }
                        Toggle("Générer le rapport automatiquement", isOn: $summaryAuto)
                            .tint(Color.timbreViolet)
                    } header: {
                        Text("Rapport de réunion")
                    } footer: {
                        Text("Le texte du transcript est envoyé au service choisi (\(summaryService.displayName)) pour la rédaction, avec sa propre clé API stockée dans le Trousseau. Les catégories regroupent tes instructions par type de réunion.")
                    }
                    .listRowBackground(Color.timbreSurface.opacity(0.55))
                    .onChange(of: summaryService) { old, new in
                        SummaryPreferences.setModel(summaryModel, for: old)
                        summaryModel = SummaryPreferences.model(for: new)
                        summaryKey = SummaryServiceConfiguration.apiKey(for: new) ?? ""
                    }

                    Section {
                        Toggle("Garder l'historique des dictées", isOn: $keepHistory)
                            .tint(Color.timbreViolet)
                    } footer: {
                        Text("Texte uniquement, stocké sur cet iPhone. Permet de retrouver une dictée et alimente le bouton « Dernière dictée » du clavier. Désactiver efface aussi la dernière dictée du clavier.")
                    }
                    .listRowBackground(Color.timbreSurface.opacity(0.55))

                    if saveFailed {
                        Label("Impossible d'enregistrer la clé dans le Trousseau.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.timbreDanger)
                            .listRowBackground(Color.clear)
                    }

                    if savedConfirmation {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(LinearGradient.timbreAccent)
                            Text("Enregistré")
                                .foregroundStyle(Color.timbreTextPrimary)
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Réglages")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        save()
                    }
                    .tint(Color.timbreViolet)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
            .onAppear(perform: load)
        }
        .preferredColorScheme(.dark)
    }

    private func load() {
        // `try?` volontaire ici : pré-remplir un champ de formulaire n'est
        // pas un chemin critique — une clé absente ou une erreur Keychain
        // laissent simplement le champ vide, sans casser l'écran.
        if let key = try? store.load() {
            apiKey = key
        }
        vocabulary = DictationPreferences.vocabularyPrompt
        cleanupEnabled = DictationPreferences.cleanupEnabled
        language = DictationPreferences.language
        keepHistory = DictationPreferences.keepHistory
        summaryService = SummaryPreferences.service
        summaryModel = SummaryPreferences.model
        summaryCustomURL = SummaryPreferences.customBaseURL
        summaryKey = SummaryServiceConfiguration.apiKey(for: summaryService) ?? ""
        summaryAuto = SummaryPreferences.autoGenerate
    }

    private func save() {
        DictationPreferences.vocabularyPrompt = vocabulary
        DictationPreferences.cleanupEnabled = cleanupEnabled
        DictationPreferences.language = language
        DictationPreferences.keepHistory = keepHistory
        SummaryPreferences.service = summaryService
        SummaryPreferences.setModel(summaryModel, for: summaryService)
        SummaryPreferences.customBaseURL = summaryCustomURL
        SummaryPreferences.autoGenerate = summaryAuto
        // Clé du service de rapport : comme la clé Groq, jamais écrasée par
        // une valeur vide. Groq réutilise la clé de la dictée (déjà gérée).
        if summaryService != .groq, !summaryKey.isEmpty {
            do {
                try SummaryServiceConfiguration.keyStore(for: summaryService).save(summaryKey)
            } catch {
                saveFailed = true
            }
        }
        if !keepHistory {
            DictationChannel().saveLastResult(nil)
        }

        // Le vocabulaire (potentiellement vidé volontairement) se sauvegarde
        // toujours ; la clé API, elle, ne s'écrase jamais avec une valeur
        // vide pour éviter d'effacer une clé déjà enregistrée par erreur.
        saveFailed = false
        guard !apiKey.isEmpty else {
            savedConfirmation = true
            return
        }
        do {
            try store.save(apiKey)
            savedConfirmation = true
        } catch {
            savedConfirmation = false
            saveFailed = true
        }
    }
}

#Preview {
    SettingsView()
}
