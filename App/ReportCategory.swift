//
//  ReportCategory.swift
//  Timbre
//

import Foundation
import TimbreTranscription

/// Catégorie de rapport : un nom, un format de sortie et des instructions
/// libres (ADR-0009). Ex. « Réunion client », « Brainstorm », « Cours ».
struct ReportCategory: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var format: ReportFormat
    var instructions: String

    init(id: UUID = UUID(), name: String, format: ReportFormat, instructions: String = "") {
        self.id = id
        self.name = name
        self.format = format
        self.instructions = instructions
    }

    /// Libellé du format dans les écrans.
    static func formatName(_ format: ReportFormat) -> String {
        switch format {
        case .structured: String(localized: "Compte rendu structuré")
        case .short: String(localized: "Résumé court")
        case .free: String(localized: "Libre")
        }
    }
}

/// Catégories persistées en `UserDefaults` (JSON, non sensible). Au moins une
/// catégorie existe toujours : à défaut, les catégories d'origine sont
/// recréées.
struct ReportCategoryStore {
    static let shared = ReportCategoryStore()

    static let structuredID = UUID(uuidString: "6F0C2A10-0000-4000-8000-000000000001")!
    static let shortID = UUID(uuidString: "6F0C2A10-0000-4000-8000-000000000002")!
    static let legacyID = UUID(uuidString: "6F0C2A10-0000-4000-8000-000000000003")!

    /// Instructions par défaut d'avant les catégories (#43) : permet de ne
    /// migrer que celles que l'utilisateur avait vraiment personnalisées.
    static let legacyDefaultInstructions = """
        Structure le compte rendu ainsi : 1) Résumé en 3 à 5 phrases ; \
        2) Points clés par sujet ; 3) Décisions prises ; 4) Actions à mener \
        (qui, quoi, échéance si elle est citée) ; 5) Questions restées \
        ouvertes. Reste factuel et concis.
        """

    private static let categoriesKey = "fr.dafffyl.timbre.summary.categories"
    private static let selectedKey = "fr.dafffyl.timbre.summary.selectedCategory"
    private static let legacyInstructionsKey = "fr.dafffyl.timbre.summary.instructions"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var categories: [ReportCategory] {
        get {
            if let data = defaults.data(forKey: Self.categoriesKey),
                let decoded = try? JSONDecoder().decode([ReportCategory].self, from: data), !decoded.isEmpty
            {
                return decoded
            }
            return seeded()
        }
        nonmutating set {
            let value = newValue.isEmpty ? seeded() : newValue
            // `try?` volontaire : un encodage qui échouerait (impossible pour
            // ce type) laisserait simplement les catégories précédentes.
            if let data = try? JSONEncoder().encode(value) {
                defaults.set(data, forKey: Self.categoriesKey)
            }
        }
    }

    /// Dernière catégorie utilisée ; repli sur la première si elle a été
    /// supprimée.
    var selected: ReportCategory {
        let all = categories
        let id = defaults.string(forKey: Self.selectedKey).flatMap(UUID.init(uuidString:))
        return all.first { $0.id == id } ?? all[0]
    }

    func select(_ id: UUID) {
        defaults.set(id.uuidString, forKey: Self.selectedKey)
    }

    func category(id: UUID) -> ReportCategory? {
        categories.first { $0.id == id }
    }

    func update(_ category: ReportCategory) {
        var all = categories
        if let index = all.firstIndex(where: { $0.id == category.id }) {
            all[index] = category
        } else {
            all.append(category)
        }
        categories = all
    }

    /// Refuse de supprimer la dernière catégorie.
    @discardableResult
    func delete(id: UUID) -> Bool {
        var all = categories
        guard all.count > 1 else { return false }
        all.removeAll { $0.id == id }
        categories = all
        return true
    }

    /// Catégories d'origine, plus celle qui reprend les instructions
    /// personnalisées d'avant (si l'utilisateur en avait écrit).
    private func seeded() -> [ReportCategory] {
        var result = [
            ReportCategory(id: Self.structuredID, name: String(localized: "Compte rendu"), format: .structured),
            ReportCategory(id: Self.shortID, name: String(localized: "Résumé court"), format: .short),
        ]
        let legacy = (defaults.string(forKey: Self.legacyInstructionsKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !legacy.isEmpty, legacy != Self.legacyDefaultInstructions.trimmingCharacters(in: .whitespacesAndNewlines) {
            result.append(
                ReportCategory(
                    id: Self.legacyID, name: String(localized: "Mes instructions"), format: .free, instructions: legacy))
        }
        return result
    }
}
