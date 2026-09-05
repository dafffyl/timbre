import UIKit

/// `scene(_:willConnectTo:options:)` couvre le lancement à froid (l'app
/// n'existait pas, l'URL fait partie des `connectionOptions`).
/// `scene(_:openURLContexts:)` couvre le cas à chaud (l'app tournait déjà).
/// Les deux écrivent dans `LaunchURLRouter`, que la vue SwiftUI observe.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let url = connectionOptions.urlContexts.first?.url {
            LaunchURLRouter.shared.pendingURL = url
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        if let url = URLContexts.first?.url {
            LaunchURLRouter.shared.pendingURL = url
        }
    }
}
