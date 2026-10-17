//
//  TranscriptExportFile.swift
//  Timbre
//

import CoreTransferable
import UniformTypeIdentifiers

/// Fichier d'export partagé via `ShareLink` : écrit dans le dossier
/// temporaire seulement au moment du partage (pas à chaque rendu de la
/// vue), sous un vrai nom de fichier (`.md`, `.srt`) pour que les apps de
/// destination reconnaissent le format.
struct TranscriptExportFile: Transferable {
    let fileName: String
    let contents: String
    let type: UTType

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { file in
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(file.fileName)
            try Data(file.contents.utf8).write(to: url)
            return SentTransferredFile(url)
        }
    }

    static func markdown(contents: String, baseName: String) -> TranscriptExportFile {
        TranscriptExportFile(
            fileName: "\(baseName).md", contents: contents,
            type: UTType(filenameExtension: "md") ?? .plainText)
    }

    static func srt(contents: String, baseName: String) -> TranscriptExportFile {
        TranscriptExportFile(
            fileName: "\(baseName).srt", contents: contents,
            type: UTType(filenameExtension: "srt") ?? .plainText)
    }
}
