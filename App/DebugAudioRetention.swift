//
//  DebugAudioRetention.swift
//  Timbre
//

#if DEBUG
import Foundation

/// Garde une copie locale de l'audio d'une réunion **dans les builds Debug
/// seulement** (jamais Release), pour mesurer la qualité de la diarisation
/// sur de vrais enregistrements : le pipeline supprime sinon l'audio dès que
/// le transcript est sauvegardé (ADR-0005). Dossier `Documents/DebugRecordings`
/// de l'app, exclu des sauvegardes ; récupéré à la demande avec
/// `devicectl device copy from` après accord de l'utilisateur, jamais envoyé
/// ailleurs. Le contenu peut inclure la voix de tiers : à supprimer après usage.
enum DebugAudioRetention {
    static func keep(_ audioURL: URL, meetingID: UUID) {
        do {
            let fileManager = FileManager.default
            var directory = try fileManager.url(
                for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
            ).appendingPathComponent("DebugRecordings", isDirectory: true)
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)

            let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false))
                .replacingOccurrences(of: ":", with: "-")
            let destination = directory.appendingPathComponent("\(stamp)-\(meetingID.uuidString).m4a")
            try fileManager.copyItem(at: audioURL, to: destination)
        } catch {
            // Outil de développement : un échec ne doit jamais gêner la réunion.
            print("DebugAudioRetention : copie impossible — \(error.localizedDescription)")
        }
    }
}
#endif
