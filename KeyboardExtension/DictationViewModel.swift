import Foundation
import TimbreCore
import TimbreSecurity

/// Pilote la machine à états du cycle de dictée côté clavier.
///
/// Depuis ADR-0002, l'utilisateur reste sur le clavier pendant tout
/// l'enregistrement et la transcription (l'app conteneur enregistre
/// réellement en arrière-plan) — seul le tout début (`.opening`, le temps
/// que l'app confirme avoir démarré) implique une brève absence du
/// clavier. Le polling est donc justifié pendant `.recording`/
/// `.transcribing` : le clavier n'est plus suspendu à ce moment-là,
/// contrairement à l'ancien flux (Phase 3) où tout se passait dans l'app.
///
/// Le jeton de la requête en cours (`pendingKey`) vit dans
/// `UserDefaults.standard` — le stockage *propre* à l'extension, distinct de
/// l'App Group, disponible même sans Full Access. Il doit survivre à la mort
/// du process de l'extension, donc il ne peut pas être une simple variable
/// en mémoire.
@Observable
final class DictationViewModel {
    enum State: Equatable {
        case idle
        case fullAccessRequired
        case opening
        case recording
        case transcribing
        case error(String)
    }

    private(set) var state: State = .idle

    /// Appelé quand un résultat prêt est trouvé pendant le polling — le
    /// view model n'a pas accès au `textDocumentProxy`, l'insertion reste
    /// la responsabilité du `KeyboardViewController`.
    var onResultReady: ((String) -> Void)?

    private let channel = DictationChannel()
    private let pendingKey = "fr.dafffyl.timbre.pendingRequestID"
    private let pendingTimeout: TimeInterval = 20
    private let transcribingTimeout: TimeInterval = 30
    private var pollTimer: Timer?

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
        // (dismissError) — sinon la prochaine vérification l'effacerait
        // avant même que l'utilisateur ait pu la lire.
        if case .error = state {
            return nil
        }

        guard let pendingID = currentPendingID() else {
            stopPolling()
            state = .idle
            return nil
        }

        guard let request = channel.read(), request.id == pendingID else {
            // Pas de requête, ou jeton différent (périmée/annulée) : on abandonne.
            clearPending()
            stopPolling()
            state = .idle
            return nil
        }

        switch request.status {
        case .pending:
            if Date().timeIntervalSince(request.statusUpdatedAt) > pendingTimeout {
                giveUp(message: "Timbre n'a pas répondu — réessaie.")
            } else {
                state = .opening
                startPollingIfNeeded(hasFullAccess: hasFullAccess)
            }
            return nil

        case .recording:
            state = .recording
            startPollingIfNeeded(hasFullAccess: hasFullAccess)
            return nil

        case .transcribing:
            if Date().timeIntervalSince(request.statusUpdatedAt) > transcribingTimeout {
                giveUp(message: "La transcription a pris trop de temps — réessaie.")
            } else {
                state = .transcribing
                startPollingIfNeeded(hasFullAccess: hasFullAccess)
            }
            return nil

        case .ready:
            clearPending()
            stopPolling()
            state = .idle
            return request.resultText

        case .failed:
            clearPending()
            stopPolling()
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
        state = .opening
        return URL(string: "timbre://dictate")
    }

    /// Signale à l'app (vivante en arrière-plan, ADR-0002) de terminer
    /// l'enregistrement et de transcrire. Ne libère pas le jeton local — on
    /// attend encore le résultat, le polling prend le relais pour l'UI.
    func stopRecording() {
        guard let pendingID = currentPendingID(),
            var request = channel.read(), request.id == pendingID
        else { return }
        request.stopRequested = true
        channel.write(request)
    }

    /// Abandonne entièrement (que ce soit avant, pendant, ou après
    /// l'enregistrement) — vider le canal partagé est le signal que l'app
    /// interprète comme une annulation à son prochain contrôle.
    func cancel() {
        stopPolling()
        clearPending()
        channel.clear()
        state = .idle
    }

    /// Valide/efface une erreur affichée — seul moyen de revenir à `idle`
    /// depuis `.error`, volontairement manuel (voir `checkForUpdate`).
    func dismissError() {
        state = .idle
    }

    /// Revérifie périodiquement pendant l'attente — pertinent depuis
    /// ADR-0002 puisque le clavier reste au premier plan (dans l'app hôte)
    /// pendant `.recording`/`.transcribing`, contrairement à l'ancien flux.
    private func startPollingIfNeeded(hasFullAccess: Bool) {
        guard pollTimer == nil else { return }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            if let text = self.checkForUpdate(hasFullAccess: hasFullAccess) {
                self.onResultReady?(text)
            }
        }
    }

    private func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    private func giveUp(message: String) {
        clearPending()
        stopPolling()
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
