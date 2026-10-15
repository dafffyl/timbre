/// Type de connexion réseau courant — juste assez de granularité pour
/// décider s'il est acceptable de lancer un téléchargement de ~500 Mo
/// (ADR-0004) sans risquer une facture data ou une coupure en plein milieu.
public enum NetworkConnectionType: Sendable, Equatable {
    case wifi
    case cellular
    /// Partage de connexion, VPN, etc. — traité comme non-Wi-Fi par défaut
    /// dans `ModelProvisioningCoordinator` (ADR-0004, cas limite 4) : on ne
    /// peut pas garantir l'absence de coût data.
    case other
    case unavailable
}

/// Interface d'interrogation du réseau — permet de tester
/// `ModelProvisioningCoordinator` sans dépendre d'un vrai état réseau
/// (`Network.framework` côté implémentation concrète, à écrire avec l'UI qui
/// consommera ce module, voir ADR-0004).
public protocol NetworkStatusProvider: Sendable {
    func currentConnectionType() async -> NetworkConnectionType
}
