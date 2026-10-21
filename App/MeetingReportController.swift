//
//  MeetingReportController.swift
//  Timbre
//

import Foundation
import TimbreDiarization
import TimbreSecurity
import TimbreTranscription

/// Génère le rapport d'une réunion et le persiste dans l'historique.
@MainActor
@Observable
final class MeetingReportController {
    enum State: Equatable {
        case idle
        case generating
        case failed(String)
    }

    private(set) var state: State = .idle

    private let provider: () throws -> any MeetingSummaryProvider
    private let store: any MeetingHistoryStore

    init(
        provider: @escaping () throws -> any MeetingSummaryProvider = SummaryServiceConfiguration.makeProvider,
        store: any MeetingHistoryStore = DiarizationEnvironment.historyStore
    ) {
        self.provider = provider
        self.store = store
    }

    /// Renvoie l'enregistrement mis à jour (ou `nil` en cas d'échec : l'état
    /// porte alors le message). Un rapport existant n'est remplacé qu'en cas
    /// de succès.
    func generate(
        for record: MeetingRecord, instructions: String, format: ReportFormat = .free, categoryName: String? = nil
    ) async -> MeetingRecord? {
        state = .generating
        let transcript = TranscriptFormatting.plainText(for: record.turns, names: record.speakerNames)

        do {
            let text = try await provider().summarize(
                MeetingSummaryRequest(
                    transcript: transcript,
                    instructions: instructions,
                    outputLanguage: SummaryPreferences.outputLanguageName,
                    format: format
                )
            )
            var updated = record
            updated.report = MeetingReport(
                text: text, instructions: instructions,
                categoryName: categoryName, serviceLabel: SummaryPreferences.serviceLabel)
            store.update(updated)
            state = .idle
            return updated
        } catch is CancellationError {
            state = .idle
            return nil
        } catch {
            state = .failed(Self.message(for: error))
            return nil
        }
    }

    static func message(for error: Error, service: SummaryService = SummaryPreferences.service) -> String {
        guard let error = error as? SummaryError else { return "Impossible de générer le rapport." }
        let name = service.displayName
        switch error {
        case .missingAPIKey:
            return "Clé API \(name) manquante — configure-la dans les réglages."
        case .missingModel:
            return "Aucun modèle choisi pour \(name) — choisis-en un dans les réglages."
        case .invalidEndpoint:
            return "Adresse du service invalide — elle doit commencer par https://."
        case .emptyTranscript:
            return "Le transcript est vide : rien à résumer."
        case .network:
            return "Problème réseau — vérifie ta connexion et réessaie."
        case .rateLimited:
            return "Trop de requêtes envoyées à \(name) — réessaie dans un instant, ou choisis un modèle plus léger dans les réglages."
        case .server(let statusCode, _) where statusCode == 401 || statusCode == 403:
            return "Clé API \(name) refusée (code \(statusCode)) — vérifie-la dans les réglages."
        case .server(404, _):
            return "Modèle introuvable chez \(name) (code 404) — il a peut-être été retiré. Choisis-en un autre dans les réglages."
        case .server(let statusCode, _):
            return "Erreur \(name) (code \(statusCode)) pendant la génération du rapport."
        case .invalidResponse, .decoding:
            return "Réponse inattendue du modèle — réessaie."
        }
    }
}
