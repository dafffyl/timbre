/// État du provisionnement des modèles de diarisation — voir
/// `ModelProvisioningCoordinator` pour la logique qui produit ces états.
public enum ModelProvisioningState: Sendable, Equatable {
    /// Modèles prêts (déjà provisionnés, ou provisionnement qui vient de
    /// réussir) — la diarisation peut démarrer.
    case ready
    /// Consentement pas encore donné pour le téléchargement initial (~500 Mo,
    /// ADR-0004) — l'appelant doit présenter le choix à l'utilisateur puis
    /// appeler `grantConsent()`.
    case needsConsent
    /// Consentement donné mais pas sur Wi-Fi actuellement — jamais de
    /// dérogation automatique sur cellulaire (décision produit, ADR-0004).
    case needsWiFi
    /// Échec (réseau coupé en cours de route, erreur du moteur) — pas un
    /// état permanent, la prochaine tentative repart de `.needsWiFi`/
    /// `.needsConsent` selon l'état réel (ADR-0004, cas limite 3).
    case failed(String)
}
