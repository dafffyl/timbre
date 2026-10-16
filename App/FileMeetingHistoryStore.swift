//
//  FileMeetingHistoryStore.swift
//  Timbre
//

import Foundation
import TimbreDiarization

/// Implémentation concrète de `MeetingHistoryStore` — un seul fichier JSON
/// dans Application Support (pas Documents : pas destiné à être visible de
/// l'utilisateur via le Finder/l'app Fichiers, contrairement à Documents).
/// Un fichier par réunion serait plus robuste à grande échelle, mais un seul
/// tableau JSON reste largement suffisant pour un usage personnel (des
/// dizaines/centaines de réunions, quelques Ko de texte chacune) — pas de
/// raison de complexifier avant que ça pose un problème réel.
struct FileMeetingHistoryStore: MeetingHistoryStore {
    private let fileURL: URL

    init(fileURL: URL = FileMeetingHistoryStore.defaultFileURL()) {
        self.fileURL = fileURL
    }

    private static func defaultFileURL() -> URL {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("meetings.json")
    }

    func loadAll() -> [MeetingRecord] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        guard let records = try? JSONDecoder().decode([MeetingRecord].self, from: data) else {
            // Fichier présent mais illisible : le traiter comme vide
            // l'écraserait au prochain `save()` et perdrait tout l'historique.
            // On le met de côté pour qu'il reste récupérable.
            quarantineCorruptFile()
            return []
        }
        return records.sorted { $0.recordedAt > $1.recordedAt }
    }

    func save(_ record: MeetingRecord) {
        var all = loadAll()
        all.append(record)
        persist(all)
    }

    func update(_ record: MeetingRecord) {
        var all = loadAll()
        guard let index = all.firstIndex(where: { $0.id == record.id }) else { return }
        all[index] = record
        persist(all)
    }

    func delete(id: MeetingRecord.ID) {
        persist(loadAll().filter { $0.id != id })
    }

    private func quarantineCorruptFile() {
        let stamp = Int(Date().timeIntervalSince1970)
        let backup = fileURL.deletingLastPathComponent().appendingPathComponent("meetings.corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: fileURL, to: backup)
    }

    private func persist(_ records: [MeetingRecord]) {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
