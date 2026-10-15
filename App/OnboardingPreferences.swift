//
//  OnboardingPreferences.swift
//  Timbre
//

import Foundation

/// Étapes de configuration que l'app ne peut pas déduire elle-même : seul
/// le clavier connaît son `hasFullAccess`, et il ne peut pas le signaler à
/// l'app sans… Full Access (C3, CLAUDE.md). On garde donc la confirmation de
/// l'utilisateur, dans `UserDefaults.standard` comme `DictationPreferences`.
enum OnboardingPreferences {
    private static let fullAccessKey = "fr.dafffyl.timbre.onboarding.fullAccessConfirmed"
    private static let firstDictationKey = "fr.dafffyl.timbre.onboarding.firstDictationDone"
    private static let keyboardBundleID = "fr.dafffyl.timbre.keyboard"

    static var fullAccessConfirmed: Bool {
        get { UserDefaults.standard.bool(forKey: fullAccessKey) }
        set { UserDefaults.standard.set(newValue, forKey: fullAccessKey) }
    }

    static var firstDictationDone: Bool {
        get { UserDefaults.standard.bool(forKey: firstDictationKey) }
        set { UserDefaults.standard.set(newValue, forKey: firstDictationKey) }
    }

    /// Le clavier est ajouté dans Réglages > Général > Clavier : iOS en
    /// garde la liste (`AppleKeyboards`, identifiants de bundle) dans les
    /// préférences globales, lisibles sans API privée.
    static func isKeyboardEnabled(
        keyboards: [String]? = UserDefaults.standard.object(forKey: "AppleKeyboards") as? [String]
    ) -> Bool {
        (keyboards ?? []).contains { $0.hasPrefix(keyboardBundleID) }
    }
}

/// État pur de la checklist — séparé de la vue pour être testable sans UI.
struct OnboardingProgress: Equatable {
    var hasAPIKey: Bool
    var keyboardEnabled: Bool
    var fullAccessConfirmed: Bool
    var firstDictationDone: Bool

    var isComplete: Bool {
        hasAPIKey && keyboardEnabled && fullAccessConfirmed && firstDictationDone
    }

    var completedCount: Int {
        [hasAPIKey, keyboardEnabled, fullAccessConfirmed, firstDictationDone].filter { $0 }.count
    }
}
