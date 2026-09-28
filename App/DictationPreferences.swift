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
    private static let cleanupEnabledKey = "fr.dafffyl.timbre.cleanupEnabled"

    /// Désactivé par défaut (`bool(forKey:)` renvoie `false` en l'absence de
    /// valeur) : la passe de nettoyage LLM est une amélioration non éprouvée
    /// à l'usage — la dictée littérale reste le comportement par défaut tant
    /// qu'elle n'a pas fait ses preuves.
    static var cleanupEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: cleanupEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: cleanupEnabledKey) }
    }
}
