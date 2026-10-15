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

    /// Page "123" — mêmes lignes que le clavier système iOS en français pour
    /// les caractères les plus fréquents (pas la page "#+=" secondaire, plus
    /// rare, laissée pour un incrément ultérieur).
    public static let numbersAndPunctuation = KeyboardLayout(rows: [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["-", "/", ":", ";", "(", ")", "€", "&", "@", "\""],
        [".", ",", "?", "!", "'"],
    ])
}

/// Variantes accentuées proposées par appui long sur une lettre — même
/// mécanisme que le clavier système, indispensable pour écrire du français
/// normalement (le clavier de base n'a aucun accent). Clé toujours en
/// minuscule : `KeyboardView` applique la casse selon l'état du shift au
/// moment de l'affichage/l'insertion, cette table ne connaît pas la casse.
public enum DiacriticVariants {
    private static let table: [String: [String]] = [
        "a": ["à", "â", "æ"],
        "e": ["é", "è", "ê", "ë"],
        "i": ["î", "ï"],
        "o": ["ô", "œ"],
        "u": ["ù", "û", "ü"],
        "c": ["ç"],
        "n": ["ñ"],
    ]

    /// `[]` si la lettre n'a pas de variante — l'appelant n'a pas besoin de
    /// vérifier l'existence de la clé au préalable.
    public static func variants(for letter: String) -> [String] {
        table[letter.lowercased()] ?? []
    }
}
