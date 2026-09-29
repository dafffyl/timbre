/// Orchestre le provisionnement des modèles de diarisation en respectant la
/// décision produit (ADR-0004) : jamais de téléchargement (~500 Mo) sans
/// Wi-Fi et sans consentement explicite, sauf si ça a déjà réussi une fois
/// sur cet appareil (voir le cas limite 1 de l'ADR pour la limite assumée de
/// cette détection).
public actor ModelProvisioningCoordinator {
    private let provider: any DiarizationProvider
    private let networkStatus: any NetworkStatusProvider
    private let stateStore: any ModelProvisioningStateStore

    public init(
        provider: any DiarizationProvider,
        networkStatus: any NetworkStatusProvider,
        stateStore: any ModelProvisioningStateStore
    ) {
        self.provider = provider
        self.networkStatus = networkStatus
        self.stateStore = stateStore
    }

    /// À appeler avant toute diarisation. Idempotent : rappelable autant de
    /// fois que nécessaire (ex. l'UI la relance après un changement de
    /// réseau) sans effet de bord si les modèles sont déjà prêts.
    public func ensureModelsReady() async -> ModelProvisioningState {
        if stateStore.hasCompletedProvisioningBefore() {
            return await attemptPrepare()
        }
        guard stateStore.hasConsentedToDownload() else {
            return .needsConsent
        }
        guard await networkStatus.currentConnectionType() == .wifi else {
            return .needsWiFi
        }
        return await attemptPrepare()
    }

    /// À appeler après que l'utilisateur a explicitement accepté le
    /// téléchargement (UI, hors de ce module) — enregistre le consentement
    /// puis rejoue `ensureModelsReady()` (qui vérifiera alors le Wi-Fi).
    public func grantConsent() async -> ModelProvisioningState {
        stateStore.recordConsent()
        return await ensureModelsReady()
    }

    private func attemptPrepare() async -> ModelProvisioningState {
        do {
            try await provider.prepareModels()
            stateStore.recordProvisioningCompleted()
            return .ready
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
