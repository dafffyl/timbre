/// Persistance des deux faits dont `ModelProvisioningCoordinator` a besoin
/// pour ne jamais redemander Wi-Fi/consentement une fois que ça a déjà
/// marché une fois — même schéma que `DictationChannel` (méthodes plutôt que
/// propriétés `{ get set }`, pour rester appelable via un existential
/// protocol sans complication de mutabilité).
public protocol ModelProvisioningStateStore: Sendable {
    func hasConsentedToDownload() -> Bool
    func recordConsent()

    func hasCompletedProvisioningBefore() -> Bool
    func recordProvisioningCompleted()
}
