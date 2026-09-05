import Foundation
import TimbreCore

/// Seul point d'accès au `DictationRequest` partagé via l'App Group.
/// Sans Full Access, `UserDefaults(suiteName:)` renvoie un conteneur
/// inaccessible depuis l'extension clavier (C3) — l'appelant doit vérifier
/// `hasFullAccess` avant d'utiliser ce canal, cette classe ne le fait pas
/// elle-même (elle n'a pas accès à `UIInputViewController`).
public struct DictationChannel: Sendable {
    private static let appGroupID = "group.fr.dafffyl.timbre"
    private static let storageKey = "dictationRequest"

    public init() {}

    // Recréé à la demande plutôt que stocké : UserDefaults n'est pas
    // Sendable dans le SDK, une propriété stockée l'aurait empêché de
    // conformer proprement à Sendable.
    private var defaults: UserDefaults? {
        UserDefaults(suiteName: Self.appGroupID)
    }

    public func write(_ request: DictationRequest) {
        guard let data = try? JSONEncoder().encode(request) else { return }
        defaults?.set(data, forKey: Self.storageKey)
    }

    public func read() -> DictationRequest? {
        guard let data = defaults?.data(forKey: Self.storageKey) else { return nil }
        return try? JSONDecoder().decode(DictationRequest.self, from: data)
    }

    public func clear() {
        defaults?.removeObject(forKey: Self.storageKey)
    }
}
