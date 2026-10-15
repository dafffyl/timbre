//
//  NWPathNetworkStatusProvider.swift
//  Timbre
//

import Foundation
import Network
import TimbreDiarization

/// Implémentation concrète de `NetworkStatusProvider` via `Network.framework`
/// — l'abstraction vit dans `TimbreDiarization` pour rester testable sans
/// vrai réseau, cette classe est le seul point qui touche à la véritable
/// API système.
struct NWPathNetworkStatusProvider: NetworkStatusProvider {
    func currentConnectionType() async -> NetworkConnectionType {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { path in
                continuation.resume(returning: Self.connectionType(for: path))
                monitor.cancel()
            }
            monitor.start(queue: DispatchQueue.global(qos: .userInitiated))
        }
    }

    /// `path.isExpensive` plutôt que `usesInterfaceType(.wifi)` seul : un
    /// partage de connexion (hotspot personnel) s'annonce comme une
    /// interface Wi-Fi alors que les données viennent en réalité du
    /// cellulaire d'un autre appareil — `isExpensive` couvre justement ce
    /// cas (documenté par Apple comme vrai pour le cellulaire ET les
    /// hotspots personnels), cohérent avec l'intention réelle de la
    /// décision produit ("jamais de coût data caché"), pas seulement sa
    /// formulation littérale ("Wi-Fi").
    private static func connectionType(for path: NWPath) -> NetworkConnectionType {
        guard path.status == .satisfied else { return .unavailable }
        if path.usesInterfaceType(.wifi), !path.isExpensive {
            return .wifi
        }
        if path.usesInterfaceType(.cellular) {
            return .cellular
        }
        return .other
    }
}
