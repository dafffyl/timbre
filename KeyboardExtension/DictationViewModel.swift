import Foundation
import TimbreCore
import TimbreSecurity

/// Pilote la machine à états du cycle de dictée côté clavier.
///
/// Le jeton de la requête en cours (`pendingKey`) vit dans
/// `UserDefaults.standard` — le stockage *propre* à l'extension, distinct de
/// l'App Group, disponible même sans Full Access. Il doit survivre à la mort
/// du process de l'extension (C5 : rien ne garantit qu'on reverra jamais ce
/// process), donc il ne peut pas être une simple variable en mémoire.
///
/// Pas de polling/minuterie : dès que l'utilisateur déclenche une dictée, le
/// clavier passe en arrière-plan (l'app conteneur prend le premier plan,
/// C5) et son process est suspendu — aucun timer ne peut tourner pendant ce
/// temps. Le seul moment où l'extension est réellement vivante pour
/// vérifier quoi que ce soit, c'est à sa réapparition (`viewWillAppear`).
///
/// Le timeout est par phase (basé sur `statusUpdatedAt`, pas `requestedAt`)
/// : un enregistrement long n'est pas une erreur (l'utilisateur contrôle sa
/// durée), mais un `.pending` ou un `.transcribing` qui traîne l'est.
@Observable
final class DictationViewModel {
    enum State: Equatable {
        case idle
        case fullAccessRequired
        case waiting(String)
        case error(String)
    }

    private(set) var state: State = .idle

    private let channel = DictationChannel()
    private let pendingKey = "fr.dafffyl.timbre.pendingRequestID"
    private let pendingTimeout: TimeInterval = 20
    private let transcribingTimeout: TimeInterval = 30

    /// À appeler à chaque apparition du clavier (`viewWillAppear`). Retourne
    /// le texte à insérer si un résultat prêt correspond au jeton attendu,
    /// sinon `nil` — mais met toujours `state` à jour pour l'UI.
    @discardableResult
    func checkForUpdate(hasFullAccess: Bool) -> String? {
        guard hasFullAccess else {
            state = .fullAccessRequired
            return nil
        }

        // Une erreur reste affichée jusqu'à validation explicite
        // (dismissError) — sinon le prochain viewWillAppear l'effacerait
        // avant même que l'utilisateur ait pu la lire.
        if case .error = state {
            return nil
        }

        guard let pendingID = currentPendingID() else {
            state = .idle
            return nil
        }

        guard let request = channel.read(), request.id == pendingID else {
            // Pas de requête, ou jeton différent (périmée/annulée) : on abandonne.
            clearPending()
            state = .idle
            return nil
        }

        let elapsedSinceStatusChange = Date().timeIntervalSince(request.statusUpdatedAt)

        switch request.status {
        case .pending:
            if elapsedSinceStatusChange > pendingTimeout {
                giveUp(message: "Timbre n'a pas répondu — réessaie.")
            } else {
                state = .waiting("Ouverture de Timbre…")
            }
            return nil

        case .recording:
            state = .waiting("Enregistrement en cours…")
            return nil

        case .transcribing:
            if elapsedSinceStatusChange > transcribingTimeout {
                giveUp(message: "La transcription a pris trop de temps — réessaie.")
            } else {
                state = .waiting("Transcription en cours…")
            }
            return nil

        case .ready:
            clearPending()
            channel.clear()
            state = .idle
            return request.resultText

        case .failed:
            clearPending()
            channel.clear()
            state = .error(request.errorMessage ?? "Échec côté app — réessaie.")
            return nil
        }
    }

    /// Démarre un nouveau cycle. Retourne l'URL à ouvrir si tout est prêt,
    /// `nil` si Full Access manque (l'appelant ne doit alors rien ouvrir).
    func startDictation(hasFullAccess: Bool) -> URL? {
        guard hasFullAccess else {
            state = .fullAccessRequired
            return nil
        }

        let newID = UUID()
        UserDefaults.standard.set(newID.uuidString, forKey: pendingKey)
        channel.write(DictationRequest(id: newID))
        state = .waiting("Ouverture de Timbre…")
        return URL(string: "timbre://dictate")
    }

    func cancel() {
        clearPending()
        channel.clear()
        state = .idle
    }

    /// Valide/efface une erreur affichée — seul moyen de revenir à `idle`
    /// depuis `.error`, volontairement manuel (voir `checkForUpdate`).
    func dismissError() {
        state = .idle
    }

    private func giveUp(message: String) {
        clearPending()
        channel.clear()
        state = .error(message)
    }

    private func currentPendingID() -> UUID? {
        guard let raw = UserDefaults.standard.string(forKey: pendingKey) else { return nil }
        return UUID(uuidString: raw)
    }

    private func clearPending() {
        UserDefaults.standard.removeObject(forKey: pendingKey)
    }
}
