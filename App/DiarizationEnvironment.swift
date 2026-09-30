//
//  DiarizationEnvironment.swift
//  Timbre
//

import TimbreDiarization

/// Point d'accès unique au coordinateur de provisionnement des modèles de
/// diarisation — même raison que `DictationController.shared` : un seul
/// `FluidAudioDiarizationProvider` (donc un seul `OfflineDiarizerManager`)
/// doit vivre pour toute l'app, pas un par écran ouvert, pour ne jamais
/// perdre l'état "modèles déjà chargés en mémoire" entre deux ouvertures de
/// l'écran de réglage — et pour que la future fonctionnalité réunion
/// réutilise ce même provider déjà préparé plutôt que d'en recréer un.
enum DiarizationEnvironment {
    /// `nonisolated` : sans ça, l'isolation MainActor par défaut du module
    /// (voir `CLAUDE.md`) s'applique à cette propriété alors qu'elle n'en a
    /// pas besoin — c'est un `let` immuable qui contient un `actor`
    /// (intrinsèquement `Sendable`), lisible sans risque depuis n'importe
    /// quel contexte, y compris la valeur par défaut d'un paramètre
    /// (`DiarizationSetupViewModel.init`), qui n'est pas garantie MainActor.
    nonisolated static let provisioningCoordinator = ModelProvisioningCoordinator(
        provider: FluidAudioDiarizationProvider(),
        networkStatus: NWPathNetworkStatusProvider(),
        stateStore: ModelProvisioningPreferences()
    )

    /// `nonisolated` pour la même raison : `FileMeetingHistoryStore` est un
    /// `struct` sans état mutable propre (tout passe par le fichier), sûr à
    /// lire depuis n'importe quel contexte.
    nonisolated static let historyStore: any MeetingHistoryStore = FileMeetingHistoryStore()
}
