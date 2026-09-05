import Foundation
import Security

/// Stockage Keychain d'une clé API. `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
/// : jamais synchronisée via iCloud, inaccessible avant le premier
/// déverrouillage après redémarrage. Jamais dans `UserDefaults`, le code, ou
/// les logs.
///
/// Pas de Keychain Access Group explicite : seule l'app conteneur lit/écrit
/// cette clé (le clavier ne fait jamais de réseau, C1) — le groupe partagé
/// documenté dans `CLAUDE.md` n'a de sens que si un second target y accède
/// un jour réellement.
public struct APIKeyStore: Sendable {
    public enum StoreError: Error, Sendable, Equatable {
        case unhandledStatus(OSStatus)
        case unexpectedData
    }

    private let service: String

    public init(service: String = "fr.dafffyl.timbre.groq-api-key") {
        self.service = service
    }

    public func save(_ key: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
        ]

        // Supprime l'ancienne valeur plutôt que d'échouer sur un doublon.
        SecItemDelete(query as CFDictionary)

        var attributes = query
        attributes[kSecValueData] = Data(key.utf8)
        attributes[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw StoreError.unhandledStatus(status)
        }
    }

    public func load() throws -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let key = String(data: data, encoding: .utf8) else {
                throw StoreError.unexpectedData
            }
            return key
        case errSecItemNotFound:
            return nil
        default:
            throw StoreError.unhandledStatus(status)
        }
    }

    public func delete() throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.unhandledStatus(status)
        }
    }
}
