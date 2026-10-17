import SwiftUI
import TimbreSecurity

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var vocabulary: String = ""
    @State private var cleanupEnabled = false
    @State private var keepHistory = true
    @State private var voiceEnabled = VoicePreferences.isEnabled
    @State private var showVoiceConsent = false
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
                        Toggle("Reconnaître les voix", isOn: Binding(
                            get: { voiceEnabled },
                            set: { newValue in
                                if newValue {
                                    showVoiceConsent = true
                                } else {
                                    voiceEnabled = false
                                    VoicePreferences.isEnabled = false
                                }
                            }
                        ))
                        .tint(Color.timbreViolet)
                        NavigationLink("Voix connues") {
                            VoiceProfilesView()
                        }
                    } header: {
                        Text("Reconnaissance des voix")
                    } footer: {
                        Text("Retrouve automatiquement le nom des personnes déjà nommées dans une réunion précédente. Empreintes stockées uniquement sur cet iPhone, jamais envoyées.")
                    }
                    .listRowBackground(Color.timbreSurface.opacity(0.55))

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
            .alert("Activer la reconnaissance des voix ?", isPresented: $showVoiceConsent) {
                Button("Activer") {
                    voiceEnabled = true
                    VoicePreferences.isEnabled = true
                }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("Timbre mémorisera une empreinte numérique de la voix des personnes que tu nommes dans tes réunions, uniquement sur cet iPhone, pour proposer leur nom la prochaine fois. C'est une donnée biométrique : prévois d'informer les participants et d'obtenir leur accord. Tu peux tout supprimer à tout moment.")
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
        voiceEnabled = VoicePreferences.isEnabled
    }

    private func save() {
        DictationPreferences.vocabularyPrompt = vocabulary
        DictationPreferences.cleanupEnabled = cleanupEnabled
        DictationPreferences.language = language
        DictationPreferences.keepHistory = keepHistory
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
