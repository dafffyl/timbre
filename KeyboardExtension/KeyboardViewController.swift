//
//  KeyboardViewController.swift
//  KeyboardExtension
//

import UIKit
import SwiftUI
import CoreFoundation
import TimbreCore

/// `enableInputClicksWhenVisible` (protocole `UIInputViewAudioFeedback`) se
/// pose sur la vue réellement affichée à l'écran, pas sur le
/// `UIInputViewController` — d'où ce sous-type dédié, posé comme `view` du
/// controller dans `loadView()`. `UIView` toute nue par ailleurs, le reste
/// du contenu (SwiftUI, bouton clavier suivant) est ajouté par-dessus comme
/// avant.
private final class InputClickView: UIView, UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}

class KeyboardViewController: UIInputViewController {

    @IBOutlet var nextKeyboardButton: UIButton!

    private let viewModel = DictationViewModel()

    /// Dernière insertion d'un espace par l'utilisateur (pas par l'app ou un
    /// résultat de dictée) — sert uniquement à détecter le double-espace,
    /// voir `insertText(fromUserTap:)`.
    private var lastSpaceInsertedAt: Date?

    override func loadView() {
        self.view = InputClickView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        setUpKeyboardView()
        setUpNextKeyboardButton()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if let text = viewModel.checkForUpdate(hasFullAccess: hasFullAccess) {
            textDocumentProxy.insertText(text)
        }
    }

    /// Requis par Apple : le bouton "clavier suivant" doit rester un vrai
    /// `UIButton` avec ce sélecteur précis pour le geste "maintenir pour
    /// voir la liste des claviers" — un simple bouton SwiftUI ne le
    /// reproduit pas. Restylé en icône hamburger et superposé en haut à
    /// gauche par-dessus la vue SwiftUI, pour matcher visuellement le
    /// design cible sans perdre ce comportement système.
    private func setUpNextKeyboardButton() {
        self.nextKeyboardButton = UIButton(type: .system)
        self.nextKeyboardButton.setImage(UIImage(systemName: "line.3.horizontal"), for: [])
        self.nextKeyboardButton.tintColor = .white
        self.nextKeyboardButton.translatesAutoresizingMaskIntoConstraints = false
        self.nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        self.view.addSubview(self.nextKeyboardButton)
        NSLayoutConstraint.activate([
            self.nextKeyboardButton.leftAnchor.constraint(equalTo: self.view.leftAnchor, constant: 14),
            self.nextKeyboardButton.topAnchor.constraint(equalTo: self.view.topAnchor, constant: 14),
            self.nextKeyboardButton.widthAnchor.constraint(equalToConstant: 32),
            self.nextKeyboardButton.heightAnchor.constraint(equalToConstant: 32),
        ])
    }

    private func setUpKeyboardView() {
        viewModel.onResultReady = { [weak self] text in
            self?.textDocumentProxy.insertText(text)
        }

        let keyboardView = KeyboardView(
            layout: .azerty,
            viewModel: viewModel,
            onKeyTap: { [weak self] text in self?.insertText(fromUserTap: text) },
            onDeleteTap: { [weak self] in self?.textDocumentProxy.deleteBackward() },
            onMicTap: { [weak self] in self?.startDictation() },
            onStopRecordingTap: { [weak self] in self?.viewModel.stopRecording() },
            onCancelTap: { [weak self] in self?.viewModel.cancel() },
            onDismissError: { [weak self] in self?.viewModel.dismissError() },
            onHapticTap: { [weak self] in self?.triggerHapticFeedback() }
        )
        let hostingController = UIHostingController(rootView: keyboardView)
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        hostingController.didMove(toParent: self)
    }

    /// Correction après retour terrain : un premier essai utilisait
    /// `AudioServicesPlaySystemSound` (vibration système brute) en
    /// affirmant à tort dans ce commentaire que le problème avait été
    /// "confirmé sur device" — ça ne l'avait pas été, seulement déduit de
    /// connaissances générales sur la plateforme. Ressenti en vrai : un buzz
    /// franc, sans rapport avec le clavier système, jugé mauvais à l'usage.
    ///
    /// Mécanisme correct, celui qu'utilise réellement le clavier système :
    /// `UIDevice.playInputClick()`, activé par `InputClickView` (voir plus
    /// haut) posée comme `view` du controller. Différence clé avec
    /// `AudioServicesPlaySystemSound` : ça respecte le réglage utilisateur
    /// (Réglages > Sons et retour haptique > Retours clavier — silencieux si
    /// désactivé, comme le vrai clavier), et ne nécessite pas Full Access
    /// (mécanisme UIKit de base, sans lien avec réseau/App Group) — d'où le
    /// retrait du `guard hasFullAccess` qui n'avait pas lieu d'être ici.
    private func triggerHapticFeedback() {
        UIDevice.current.playInputClick()
    }

    /// Point d'entrée unique pour une insertion venant d'un tap utilisateur
    /// (lettre, chiffre, ponctuation, espace) — pas pour le texte inséré par
    /// une dictée terminée (`onResultReady`/`viewWillAppear`), qui ne doit
    /// jamais déclencher la détection de double-espace. Reproduit le
    /// comportement du clavier système : un second espace tapé juste après
    /// le premier remplace les deux par ". ".
    private func insertText(fromUserTap text: String) {
        guard text == " " else {
            lastSpaceInsertedAt = nil
            textDocumentProxy.insertText(text)
            return
        }

        if let lastSpace = lastSpaceInsertedAt, Date().timeIntervalSince(lastSpace) < 0.3 {
            textDocumentProxy.deleteBackward()
            textDocumentProxy.insertText(". ")
            lastSpaceInsertedAt = nil
        } else {
            textDocumentProxy.insertText(" ")
            lastSpaceInsertedAt = Date()
        }
    }

    /// Poste toujours la notification Darwin d'abord (coût quasi nul si
    /// personne n'écoute), attend un court délai, puis n'ouvre l'app que si
    /// la requête est toujours `.pending` — c'est-à-dire que l'app n'était
    /// pas chaude (voir `DictationController`, fenêtre de grâce de 30s côté
    /// app). Si l'app a réagi à temps, aucune bascule visible.
    private func startDictation() {
        guard let requestID = viewModel.prepareNewRequest(hasFullAccess: hasFullAccess) else { return }
        postDarwinWake()

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard let url = viewModel.coldWakeURLIfStillPending(requestID) else { return }

            // extensionContext.open() est réservé aux widgets Today ; l'action
            // openURL de SwiftUI, elle, fonctionne depuis une extension clavier
            // (cf. docs/spikes/keyboard-app-roundtrip.md).
            let environment = EnvironmentValues()
            environment.openURL(url)
        }
    }

    private func postDarwinWake() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName("fr.dafffyl.timbre.wake" as CFString),
            nil,
            nil,
            true
        )
    }

    override func viewWillLayoutSubviews() {
        self.nextKeyboardButton.isHidden = !self.needsInputModeSwitchKey
        super.viewWillLayoutSubviews()
    }

    override func textWillChange(_ textInput: UITextInput?) {
        // The app is about to change the document's contents. Perform any preparation here.
    }

    override func textDidChange(_ textInput: UITextInput?) {
        // The app has just changed the document's contents, the document context has been updated.
    }

}
