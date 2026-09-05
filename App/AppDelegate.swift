import UIKit

/// Force l'utilisation de `SceneDelegate` pour la scène par défaut — c'est
/// ce qui rend `scene(_:willConnectTo:options:)` disponible malgré le
/// cycle de vie SwiftUI (`@main struct ... : App`).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: "Default Configuration",
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}
