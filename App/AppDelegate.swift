import UIKit
import CoreFoundation

/// Force l'utilisation de `SceneDelegate` pour la scène par défaut — c'est
/// ce qui rend `scene(_:willConnectTo:options:)` disponible malgré le
/// cycle de vie SwiftUI (`@main struct ... : App`).
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        registerDarwinWakeObserver()
        return true
    }

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

    /// Le clavier poste cette notification à chaque tentative de dictée,
    /// avant même de savoir si l'app est chaude (voir
    /// `DictationViewModel.prepareNewRequest`). Si `DictationController` est
    /// dans sa fenêtre de grâce, il reprend directement l'enregistrement —
    /// sinon ne fait rien, et le clavier retombe sur `openURL` de lui-même
    /// après son propre délai. Callback C, donc sans capture : uniquement
    /// des références statiques/globales (`DictationController.shared`).
    private func registerDarwinWakeObserver() {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            { _, _, _, _, _ in
                Task { @MainActor in
                    DictationController.shared.handleWakeSignal()
                }
            },
            "fr.dafffyl.timbre.wake" as CFString,
            nil,
            .deliverImmediately
        )
    }
}
