//
//  SummaryPreferences.swift
//  Timbre
//

import Foundation
import TimbreSecurity
import TimbreTranscription

/// Réglages du rapport de réunion (UserDefaults, non sensibles — les clés API
/// restent dans le Keychain). Un seul service et un seul modèle pour tous les
/// rapports (ADR-0009) ; les instructions vivent dans `ReportCategory`.
enum SummaryPreferences {
    private static let serviceKey = "fr.dafffyl.timbre.summary.service"
    private static let customURLKey = "fr.dafffyl.timbre.summary.customBaseURL"
    private static let autoGenerateKey = "fr.dafffyl.timbre.summary.autoGenerate"

    private static func modelKey(for service: SummaryService) -> String {
        "fr.dafffyl.timbre.summary.model.\(service.rawValue)"
    }

    static var service: SummaryService {
        get { UserDefaults.standard.string(forKey: serviceKey).flatMap(SummaryService.init(rawValue:)) ?? .groq }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: serviceKey) }
    }

    /// Modèle choisi pour ce service ; à défaut, le modèle par défaut du
    /// service (vide quand aucun n'est sûr — voir `SummaryService`).
    static func model(for service: SummaryService) -> String {
        UserDefaults.standard.string(forKey: modelKey(for: service)) ?? service.defaultModel
    }

    static func setModel(_ model: String, for service: SummaryService) {
        UserDefaults.standard.set(model, forKey: modelKey(for: service))
    }

    static var model: String { model(for: service) }

    static var customBaseURL: String {
        get { UserDefaults.standard.string(forKey: customURLKey) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: customURLKey) }
    }

    /// Désactivé par défaut : le rapport envoie le texte du transcript à un
    /// modèle de chat, une étape en plus de la transcription — l'utilisateur
    /// l'active explicitement.
    static var autoGenerate: Bool {
        get { UserDefaults.standard.bool(forKey: autoGenerateKey) }
        set { UserDefaults.standard.set(newValue, forKey: autoGenerateKey) }
    }

    /// « Claude (Anthropic) · claude-sonnet-5-5 » — gardé dans le rapport.
    static var serviceLabel: String {
        "\(service.displayName) · \(model)"
    }

    /// Langue du rapport : celle de la transcription ; en détection
    /// automatique, la langue de l'app. Nom en toutes lettres, dans la
    /// langue elle-même (« français », « English »).
    static var outputLanguageName: String {
        let code = DictationPreferences.languageCode ?? Locale.current.language.languageCode?.identifier ?? "fr"
        return Locale(identifier: code).localizedString(forLanguageCode: code) ?? "français"
    }
}

/// Clés API par service (Keychain) et fabrique du fournisseur courant.
enum SummaryServiceConfiguration {
    /// Groq réutilise la clé de la dictée ; chaque autre service a la sienne.
    static func keyStore(for service: SummaryService) -> APIKeyStore {
        service == .groq ? APIKeyStore() : APIKeyStore(service: "fr.dafffyl.timbre.summary-key.\(service.rawValue)")
    }

    static func apiKey(for service: SummaryService) -> String? {
        // `try?` volontaire : une erreur Keychain se traduit par « clé
        // manquante », message déjà géré partout.
        (try? keyStore(for: service).load()) ?? nil
    }

    static func makeProvider() throws -> any MeetingSummaryProvider {
        let service = SummaryPreferences.service
        return try MeetingSummaryProviderFactory.make(
            service: service,
            model: SummaryPreferences.model(for: service),
            customBaseURL: SummaryPreferences.customBaseURL,
            apiKey: { apiKey(for: service) }
        )
    }
}
