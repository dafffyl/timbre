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

    private let provider: (String) -> any MeetingSummaryProvider
    private let store: any MeetingHistoryStore

    init(
        provider: @escaping (String) -> any MeetingSummaryProvider = { model in
            GroqMeetingSummaryProvider(apiKey: { (try? APIKeyStore().load()) ?? nil }, model: model)
        },
        store: any MeetingHistoryStore = DiarizationEnvironment.historyStore
    ) {
        self.provider = provider
        self.store = store
    }

    /// Renvoie l'enregistrement mis à jour (ou `nil` en cas d'échec : l'état
    /// porte alors le message). Un rapport existant n'est remplacé qu'en cas
    /// de succès.
    func generate(for record: MeetingRecord, instructions: String) async -> MeetingRecord? {
        state = .generating
        let transcript = TranscriptFormatting.plainText(for: record.turns, names: record.speakerNames)

        do {
            let text = try await provider(SummaryPreferences.model).summarize(
                MeetingSummaryRequest(
                    transcript: transcript,
                    instructions: instructions,
                    outputLanguage: SummaryPreferences.outputLanguageName
                )
            )
            var updated = record
            updated.report = MeetingReport(text: text, instructions: instructions)
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

    static func message(for error: Error) -> String {
        guard let error = error as? SummaryError else { return "Impossible de générer le rapport." }
        switch error {
        case .missingAPIKey:
            return "Clé API Groq manquante — configure-la dans les réglages."
        case .emptyTranscript:
            return "Le transcript est vide : rien à résumer."
        case .network:
            return "Problème réseau — vérifie ta connexion et réessaie."
        case .rateLimited:
            return "Trop de requêtes envoyées à Groq — réessaie dans un instant, ou choisis le modèle rapide dans les réglages."
        case .server(let statusCode, _) where statusCode == 401 || statusCode == 403:
            return "Clé API Groq refusée (code \(statusCode)) — vérifie-la dans les réglages."
        case .server(let statusCode, _):
            return "Erreur Groq (code \(statusCode)) pendant la génération du rapport."
        case .invalidResponse, .decoding:
            return "Réponse inattendue du modèle — réessaie."
        }
    }
}
