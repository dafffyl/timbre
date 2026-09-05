/// Emplacement réservé pour le wrapper Keychain et l'accès à l'App Group
/// (Phase 2). Vide pour l'instant — son seul rôle actuel est de faire
/// exister le package, pour que la règle de dépendance du clavier
/// (`KeyboardExtension` importe uniquement `TimbreCore` et `TimbreSecurity`)
/// ait quelque chose de réel à vérifier dès la Phase 1.
public enum TimbreSecurity {}
