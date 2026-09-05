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

    override func viewDidLoad() {
        super.viewDidLoad()

        setUpNextKeyboardButton()
        setUpKeyboardView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if let text = viewModel.checkForUpdate(hasFullAccess: hasFullAccess) {
            textDocumentProxy.insertText(text)
        }
    }

    private func setUpNextKeyboardButton() {
        self.nextKeyboardButton = UIButton(type: .system)
        self.nextKeyboardButton.setTitle(NSLocalizedString("Next Keyboard", comment: "Title for 'Next Keyboard' button"), for: [])
        self.nextKeyboardButton.sizeToFit()
        self.nextKeyboardButton.translatesAutoresizingMaskIntoConstraints = false
        self.nextKeyboardButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        self.view.addSubview(self.nextKeyboardButton)
        self.nextKeyboardButton.leftAnchor.constraint(equalTo: self.view.leftAnchor).isActive = true
        self.nextKeyboardButton.bottomAnchor.constraint(equalTo: self.view.bottomAnchor).isActive = true
    }

    private func setUpKeyboardView() {
        let keyboardView = KeyboardView(
            layout: .azerty,
            viewModel: viewModel,
            onMicTap: { [weak self] in self?.startDictation() },
            onCancelTap: { [weak self] in self?.viewModel.cancel() },
            onDismissError: { [weak self] in self?.viewModel.dismissError() }
        )
        let hostingController = UIHostingController(rootView: keyboardView)
        addChild(hostingController)
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: nextKeyboardButton.topAnchor),
        ])
        hostingController.didMove(toParent: self)
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

        var textColor: UIColor
        let proxy = self.textDocumentProxy
        if proxy.keyboardAppearance == UIKeyboardAppearance.dark {
            textColor = UIColor.white
        } else {
            textColor = UIColor.black
        }
        self.nextKeyboardButton.setTitleColor(textColor, for: [])
    }

}
