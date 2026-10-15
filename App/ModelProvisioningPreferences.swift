//
//  ModelProvisioningPreferences.swift
//  Timbre
//

import Foundation
import TimbreDiarization

/// Implémentation concrète de `ModelProvisioningStateStore` —
/// `UserDefaults.standard`, même schéma que `DictationPreferences` (non
/// sensible, pas le Keychain).
struct ModelProvisioningPreferences: ModelProvisioningStateStore {
    private static let consentKey = "fr.dafffyl.timbre.diarization.hasConsentedToDownload"
    private static let completedKey = "fr.dafffyl.timbre.diarization.hasCompletedProvisioning"

    func hasConsentedToDownload() -> Bool {
        UserDefaults.standard.bool(forKey: Self.consentKey)
    }

    func recordConsent() {
        UserDefaults.standard.set(true, forKey: Self.consentKey)
    }

    func hasCompletedProvisioningBefore() -> Bool {
        UserDefaults.standard.bool(forKey: Self.completedKey)
    }

    func recordProvisioningCompleted() {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
    }
}
