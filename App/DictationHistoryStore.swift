//
//  DictationHistoryStore.swift
//  Timbre
//

import Foundation

struct DictationRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let date: Date
    var text: String

    init(id: UUID = UUID(), date: Date = Date(), text: String) {
        self.id = id
        self.date = date
        self.text = text
    }
}

/// Historique local des dictées (texte seulement, jamais l'audio) dans
/// Application Support, même approche que `FileMeetingHistoryStore`. Plafonné
/// pour rester petit ; désactivable dans les réglages
/// (`DictationPreferences.keepHistory`) puisque le texte dicté peut être
/// sensible.
struct DictationHistoryStore {
    static let maxRecords = 100

    private let fileURL: URL

    init(fileURL: URL = DictationHistoryStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    private static func defaultFileURL() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("dictations.json")
    }

    func loadAll() -> [DictationRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        guard let records = try? JSONDecoder().decode([DictationRecord].self, from: data) else {
            // Même règle que l'historique des réunions : on ne perd pas un
            // fichier illisible, on le met de côté.
            let backup = fileURL.deletingLastPathComponent()
                .appendingPathComponent("dictations.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            return []
        }
        return records.sorted { $0.date > $1.date }
    }

    func add(_ record: DictationRecord) {
        var all = loadAll()
        all.insert(record, at: 0)
        persist(Array(all.prefix(Self.maxRecords)))
    }

    func delete(id: DictationRecord.ID) {
        persist(loadAll().filter { $0.id != id })
    }

    func deleteAll() {
        persist([])
    }

    private func persist(_ records: [DictationRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}

/// Audio d'une dictée dont la transcription a échoué, conservé pour un
/// réessai depuis l'historique. Les trois plus récentes seulement ; supprimé
/// dès qu'une transcription réussit.
struct PendingDictation: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let url: URL
}

enum PendingDictationStore {
    static let maxKept = 3

    private static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("PendingDictations", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Déplace l'enregistrement dans le dossier persistant. Renvoie `nil`
    /// si le déplacement échoue (l'audio est alors perdu, comme avant).
    @discardableResult
    static func keep(audioAt url: URL) -> PendingDictation? {
        let id = UUID()
        let destination = directory.appendingPathComponent("\(id.uuidString).m4a")
        do {
            try FileManager.default.moveItem(at: url, to: destination)
        } catch {
            return nil
        }
        let all = self.all()
        for old in all.dropFirst(maxKept) {
            try? FileManager.default.removeItem(at: old.url)
        }
        return PendingDictation(id: id, date: Date(), url: destination)
    }

    static func all() -> [PendingDictation] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        return urls.compactMap { url in
            guard url.pathExtension == "m4a", let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent)
            else { return nil }
            let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
            return PendingDictation(id: id, date: date, url: url)
        }.sorted { $0.date > $1.date }
    }

    static func remove(_ pending: PendingDictation) {
        try? FileManager.default.removeItem(at: pending.url)
    }
}
