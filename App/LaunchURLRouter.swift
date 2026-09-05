import Foundation
import Observation

/// Pont entre le UISceneDelegate (UIKit, seul moyen fiable de recevoir une
/// URL de lancement à froid) et la vue SwiftUI. `.onOpenURL` seul rate
/// parfois l'URL qui a déclenché un lancement à froid — voir SceneDelegate.
@Observable
final class LaunchURLRouter {
    static let shared = LaunchURLRouter()
    private init() {}

    var pendingURL: URL?
}
