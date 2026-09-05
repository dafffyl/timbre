/// Disposition statique d'un clavier, partagée entre l'extension clavier et
/// l'app conteneur. Vit dans `TimbreCore` (zéro I/O) pour rester importable
/// depuis le clavier sans tirer de dépendance interdite.
public struct KeyboardLayout: Sendable, Equatable {
    public let rows: [[String]]

    public init(rows: [[String]]) {
        self.rows = rows
    }

    public static let azerty = KeyboardLayout(rows: [
        ["A", "Z", "E", "R", "T", "Y", "U", "I", "O", "P"],
        ["Q", "S", "D", "F", "G", "H", "J", "K", "L", "M"],
        ["W", "X", "C", "V", "B", "N"],
    ])
}
