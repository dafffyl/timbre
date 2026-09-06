//
//  KeyboardViewController.swift
//  KeyboardExtension
//

import UIKit
import SwiftUI
import TimbreCore

class KeyboardViewController: UIInputViewController {

    @IBOutlet var nextKeyboardButton: UIButton!

    private let viewModel = DictationViewModel()
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)

    override func viewDidLoad() {
        super.viewDidLoad()

        setUpKeyboardView()
        setUpNextKeyboardButton()
        impactGenerator.prepare()
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
        let keyboardView = KeyboardView(
            layout: .azerty,
            viewModel: viewModel,
            onKeyTap: { [weak self] text in self?.textDocumentProxy.insertText(text) },
            onDeleteTap: { [weak self] in self?.textDocumentProxy.deleteBackward() },
            onMicTap: { [weak self] in self?.startDictation() },
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

    /// Sans Full Access, le moteur haptique d'une extension clavier est
    /// muet — pas d'erreur, juste aucun effet. On évite l'appel plutôt que
    /// de laisser croire que ça devrait vibrer.
    private func triggerHapticFeedback() {
        guard hasFullAccess else { return }
        impactGenerator.impactOccurred()
    }

    private func startDictation() {
        guard let url = viewModel.startDictation(hasFullAccess: hasFullAccess) else { return }

        // extensionContext.open() est réservé aux widgets Today ; l'action
        // openURL de SwiftUI, elle, fonctionne depuis une extension clavier
        // (cf. docs/spikes/keyboard-app-roundtrip.md).
        Task { @MainActor in
            let environment = EnvironmentValues()
            environment.openURL(url)
        }
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
