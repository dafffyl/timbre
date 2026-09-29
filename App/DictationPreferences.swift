//
//  DictationPreferences.swift
//  Timbre
//

import Foundation

/// Vocabulaire personnalisé de l'utilisateur (noms propres, jargon
/// technique) — transmis comme `prompt` à Whisper pour améliorer la
/// reconnaissance de mots rares (voir `TranscriptionRequest.prompt`).
/// Non sensible : `UserDefaults.standard`, pas le Keychain (contrairement à
/// la clé API Groq, voir `APIKeyStore`).
///
/// Struct plutôt qu'un accès direct dupliqué dans `SettingsView` et
/// `DictationController` : une seule définition de la clé, pour éviter
/// qu'elle diverge entre l'écriture et la lecture — même raison que
/// `DictationViewModel.pendingKey` côté clavier.
enum DictationPreferences {
    private static let vocabularyKey = "fr.dafffyl.timbre.vocabularyPrompt"

    static var vocabularyPrompt: String {
        get { UserDefaults.standard.string(forKey: vocabularyKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: vocabularyKey) }
    }
}
