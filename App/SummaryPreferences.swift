//
//  SummaryPreferences.swift
//  Timbre
//

import Foundation

/// Réglages du rapport de réunion (UserDefaults, non sensibles — la clé
/// Groq reste dans le Keychain). Les instructions sont du texte libre de
/// l'utilisateur, ajouté au cadre fixe de `GroqMeetingSummaryProvider`.
enum SummaryPreferences {
    private static let instructionsKey = "fr.dafffyl.timbre.summary.instructions"
    private static let modelKey = "fr.dafffyl.timbre.summary.model"
    private static let autoGenerateKey = "fr.dafffyl.timbre.summary.autoGenerate"

    static let models: [(id: String, name: String)] = [
        ("llama-3.3-70b-versatile", String(localized: "Précis — Llama 3.3 70B")),
        ("llama-3.1-8b-instant", String(localized: "Rapide — Llama 3.1 8B")),
    ]

    static var defaultInstructions: String {
        String(localized: """
        Structure le compte rendu ainsi : 1) Résumé en 3 à 5 phrases ; \
        2) Points clés par sujet ; 3) Décisions prises ; 4) Actions à mener \
        (qui, quoi, échéance si elle est citée) ; 5) Questions restées \
        ouvertes. Reste factuel et concis.
        """)
    }

    /// Vide ou jamais défini : repli sur les instructions par défaut.
    static var instructions: String {
        get {
            let stored = UserDefaults.standard.string(forKey: instructionsKey) ?? ""
            return stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? defaultInstructions : stored
        }
        set { UserDefaults.standard.set(newValue, forKey: instructionsKey) }
    }

    static var model: String {
        get { UserDefaults.standard.string(forKey: modelKey) ?? models[0].id }
        set { UserDefaults.standard.set(newValue, forKey: modelKey) }
    }

    /// Désactivé par défaut : le rapport envoie le texte du transcript à un
    /// modèle de chat, une étape en plus de la transcription — l'utilisateur
    /// l'active explicitement.
    static var autoGenerate: Bool {
        get { UserDefaults.standard.bool(forKey: autoGenerateKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoGenerateKey) }
    }

    /// Langue du rapport : celle de la transcription ; en détection
    /// automatique, la langue de l'app. Nom en toutes lettres, dans la
    /// langue elle-même (« français », « English »).
    static var outputLanguageName: String {
        let code = DictationPreferences.languageCode ?? Locale.current.language.languageCode?.identifier ?? "fr"
        return Locale(identifier: code).localizedString(forLanguageCode: code) ?? "français"
    }
}
