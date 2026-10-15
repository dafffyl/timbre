import Testing
import Foundation

@testable import TimbreDiarization

@Test func firstRunWithoutConsentNeedsConsent() async {
    let coordinator = ModelProvisioningCoordinator(
        provider: FakeDiarizationProvider(),
        networkStatus: FakeNetworkStatusProvider(connectionType: .wifi),
        stateStore: FakeModelProvisioningStateStore()
    )

    let state = await coordinator.ensureModelsReady()

    #expect(state == .needsConsent)
}

@Test func consentedButNotOnWiFiNeedsWiFi() async {
    let coordinator = ModelProvisioningCoordinator(
        provider: FakeDiarizationProvider(),
        networkStatus: FakeNetworkStatusProvider(connectionType: .cellular),
        stateStore: FakeModelProvisioningStateStore(consented: true)
    )

    let state = await coordinator.ensureModelsReady()

    #expect(state == .needsWiFi)
}

@Test func consentedAndOnWiFiPreparesAndBecomesReady() async {
    let provider = FakeDiarizationProvider()
    let stateStore = FakeModelProvisioningStateStore(consented: true)
    let coordinator = ModelProvisioningCoordinator(
        provider: provider,
        networkStatus: FakeNetworkStatusProvider(connectionType: .wifi),
        stateStore: stateStore
    )

    let state = await coordinator.ensureModelsReady()

    #expect(state == .ready)
    #expect(await provider.prepareModelsCallCount == 1)
    #expect(stateStore.hasCompletedProvisioningBefore())
}

@Test func alreadyCompletedBeforeSkipsConsentAndWiFiChecksEntirely() async {
    let provider = FakeDiarizationProvider()
    // Ni consentement ni Wi-Fi — ne devrait bloquer sur rien puisque déjà
    // provisionné avec succès une fois (ADR-0004, cas limite 1).
    let coordinator = ModelProvisioningCoordinator(
        provider: provider,
        networkStatus: FakeNetworkStatusProvider(connectionType: .cellular),
        stateStore: FakeModelProvisioningStateStore(consented: false, completedBefore: true)
    )

    let state = await coordinator.ensureModelsReady()

    #expect(state == .ready)
    #expect(await provider.prepareModelsCallCount == 1)
}

@Test func grantConsentWithoutWiFiStillNeedsWiFiAfterward() async {
    let stateStore = FakeModelProvisioningStateStore()
    let coordinator = ModelProvisioningCoordinator(
        provider: FakeDiarizationProvider(),
        networkStatus: FakeNetworkStatusProvider(connectionType: .cellular),
        stateStore: stateStore
    )

    let state = await coordinator.grantConsent()

    #expect(state == .needsWiFi)
    #expect(stateStore.hasConsentedToDownload())
}

@Test func grantConsentOnWiFiGoesStraightToReady() async {
    let coordinator = ModelProvisioningCoordinator(
        provider: FakeDiarizationProvider(),
        networkStatus: FakeNetworkStatusProvider(connectionType: .wifi),
        stateStore: FakeModelProvisioningStateStore()
    )

    let state = await coordinator.grantConsent()

    #expect(state == .ready)
}

@Test func prepareFailureDoesNotRecordCompletionAndStaysRetryable() async {
    let provider = FakeDiarizationProvider(prepareResult: .failure(FakeError(message: "réseau coupé")))
    let stateStore = FakeModelProvisioningStateStore(consented: true)
    let coordinator = ModelProvisioningCoordinator(
        provider: provider,
        networkStatus: FakeNetworkStatusProvider(connectionType: .wifi),
        stateStore: stateStore
    )

    let firstAttempt = await coordinator.ensureModelsReady()
    #expect(firstAttempt == .failed("réseau coupé"))
    #expect(!stateStore.hasCompletedProvisioningBefore())

    // Pas bloqué dans un état d'échec permanent (ADR-0004, cas limite 3) :
    // une seconde tentative, cette fois configurée pour réussir, repart
    // normalement du contrôle Wi-Fi (déjà satisfait ici) plutôt que de
    // rester coincée sur `.failed`.
    await provider.setPrepareResult(.success)
    let secondAttempt = await coordinator.ensureModelsReady()
    #expect(secondAttempt == .ready)
}

@Test func otherConnectionTypeIsTreatedAsNonWiFi() async {
    let coordinator = ModelProvisioningCoordinator(
        provider: FakeDiarizationProvider(),
        networkStatus: FakeNetworkStatusProvider(connectionType: .other),
        stateStore: FakeModelProvisioningStateStore(consented: true)
    )

    let state = await coordinator.ensureModelsReady()

    #expect(state == .needsWiFi)
}

@Test func unavailableConnectionIsTreatedAsNonWiFi() async {
    let coordinator = ModelProvisioningCoordinator(
        provider: FakeDiarizationProvider(),
        networkStatus: FakeNetworkStatusProvider(connectionType: .unavailable),
        stateStore: FakeModelProvisioningStateStore(consented: true)
    )

    let state = await coordinator.ensureModelsReady()

    #expect(state == .needsWiFi)
}
