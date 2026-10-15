//
//  DiarizationSetupViewModel.swift
//  Timbre
//

import Observation
import TimbreDiarization

/// Pont entre `ModelProvisioningCoordinator` (un `actor`, pas observable
/// directement par SwiftUI) et la vue — même rôle que `DictationController`
/// pour le cycle de dictée.
///
/// `state` est optionnel : `nil` signifie "pas encore vérifié", distinct de
/// n'importe quel état réel — évite d'afficher un état arbitraire (deviné)
/// avant le premier appel à `refresh()`, qui peut très bien résoudre
/// immédiatement en `.ready` si tout est déjà en place.
@MainActor
@Observable
final class DiarizationSetupViewModel {
    private(set) var state: ModelProvisioningState?
    private(set) var isChecking = false

    private let coordinator: ModelProvisioningCoordinator

    init(coordinator: ModelProvisioningCoordinator = DiarizationEnvironment.provisioningCoordinator) {
        self.coordinator = coordinator
    }

    func refresh() async {
        isChecking = true
        state = await coordinator.ensureModelsReady()
        isChecking = false
    }

    func grantConsent() async {
        isChecking = true
        state = await coordinator.grantConsent()
        isChecking = false
    }
}
