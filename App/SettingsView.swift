import SwiftUI
import TimbreSecurity

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var vocabulary: String = ""
    @State private var savedConfirmation = false

    private let store = APIKeyStore()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Clé API Groq", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                } header: {
                    Text("Groq")
                } footer: {
                    Text("Stockée dans le Trousseau, jamais dans les réglages de l'app ni dans les journaux.")
                }

                Section {
                    TextField("Ex. Kubernetes, Aymeric, Groq…", text: $vocabulary, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Vocabulaire personnalisé")
                } footer: {
                    Text("Noms propres ou jargon technique fréquents — améliore leur reconnaissance par Whisper.")
                }

                if savedConfirmation {
                    Text("Enregistrée ✓")
                        .foregroundStyle(.green)
                        .font(.footnote)
                }
            }
            .navigationTitle("Réglages")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        save()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        // `try?` volontaire ici : pré-remplir un champ de formulaire n'est
        // pas un chemin critique — une clé absente ou une erreur Keychain
        // laissent simplement le champ vide, sans casser l'écran.
        if let key = try? store.load() {
            apiKey = key ?? ""
        }
        vocabulary = DictationPreferences.vocabularyPrompt
    }

    private func save() {
        DictationPreferences.vocabularyPrompt = vocabulary

        // Le vocabulaire (potentiellement vidé volontairement) se sauvegarde
        // toujours ; la clé API, elle, ne s'écrase jamais avec une valeur
        // vide pour éviter d'effacer une clé déjà enregistrée par erreur.
        guard !apiKey.isEmpty else {
            savedConfirmation = true
            return
        }
        do {
            try store.save(apiKey)
            savedConfirmation = true
        } catch {
            savedConfirmation = false
        }
    }
}

#Preview {
    SettingsView()
}
