//
//  DictationPreferences.swift
//  Timbre
//

import Foundation

/// Réglages non sensibles de la dictée — `UserDefaults.standard`, pas le
/// Keychain (contrairement à la clé API Groq, voir `APIKeyStore`).
///
/// Struct plutôt qu'un accès direct dupliqué dans `SettingsView` et
/// `DictationController` : une seule définition de chaque clé, pour éviter
/// qu'elle diverge entre l'écriture et la lecture.
enum DictationPreferences {
    private static let vocabularyKey = "fr.dafffyl.timbre.vocabularyPrompt"
    private static let cleanupEnabledKey = "fr.dafffyl.timbre.cleanupEnabled"
    private static let languageKey = "fr.dafffyl.timbre.transcriptionLanguage"

    /// Langues proposées dans les réglages — codes ISO-639-1 acceptés par
    /// Whisper. `auto` laisse Whisper détecter la langue (aucun paramètre
    /// `language` envoyé).
    static let supportedLanguages: [(code: String, name: String)] = [
        ("fr", "Français"),
        ("en", "English"),
        ("es", "Español"),
        ("de", "Deutsch"),
        ("it", "Italiano"),
        ("pt", "Português"),
        ("nl", "Nederlands"),
        ("auto", "Détection automatique"),
    ]

    /// Français par défaut : comportement historique de l'app.
    static var language: String {
        get { UserDefaults.standard.string(forKey: languageKey) ?? "fr" }
        set { UserDefaults.standard.set(newValue, forKey: languageKey) }
    }

    /// Valeur à passer à `TranscriptionRequest.language` : `nil` pour la
    /// détection automatique.
    static var languageCode: String? {
        let value = language
        return value == "auto" ? nil : value
    }

    /// Vocabulaire personnalisé de l'utilisateur (noms propres, jargon
    /// technique) — transmis comme `prompt` à Whisper pour améliorer la
    /// reconnaissance de mots rares (voir `TranscriptionRequest.prompt`).
    static var vocabularyPrompt: String {
        get { UserDefaults.standard.string(forKey: vocabularyKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: vocabularyKey) }
    }

    /// Désactivé par défaut (`bool(forKey:)` renvoie `false` en l'absence de
    /// valeur) : la passe de nettoyage LLM est une amélioration non éprouvée
    /// à l'usage — la dictée littérale reste le comportement par défaut tant
    /// qu'elle n'a pas fait ses preuves.
    static var cleanupEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: cleanupEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: cleanupEnabledKey) }
    }
}
