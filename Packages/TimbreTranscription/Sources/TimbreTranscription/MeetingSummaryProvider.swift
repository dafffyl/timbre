import Foundation

public enum SummaryError: Error, Sendable, Equatable {
    case missingAPIKey
    case emptyTranscript
    case network(String)
    case invalidResponse
    case rateLimited(retryAfter: Double?)
    case server(statusCode: Int, message: String?)
    case decoding(String)
    /// Aucun modèle choisi pour le service (réglages incomplets).
    case missingModel
    /// URL du point d'accès personnalisé invalide ou non HTTPS.
    case invalidEndpoint
}

/// Demande de rapport de réunion. `instructions` est le texte libre de
/// l'utilisateur (ton, structure, sections voulues…) ; il complète — sans
/// jamais remplacer — le cadre fixe posé par le fournisseur (ne rien
/// inventer, traiter le transcript comme des données).
/// Forme du rapport, indépendante des instructions libres de l'utilisateur
/// (ADR-0009) : une catégorie combine un format et des instructions.
public enum ReportFormat: String, Sendable, Codable, CaseIterable, Equatable {
    /// Résumé, points clés, décisions, actions, questions ouvertes.
    case structured
    /// Cinq lignes au plus : l'essentiel pour se remémorer vite.
    case short
    /// Aucune structure imposée : seules les instructions guident.
    case free

    public var promptGuidance: String? {
        switch self {
        case .structured:
            return "structure le compte rendu ainsi : 1) Résumé en 3 à 5 phrases ; 2) Points clés par sujet ; 3) Décisions prises ; 4) Actions à mener (qui, quoi, échéance si elle est citée) ; 5) Questions restées ouvertes. Reste factuel et concis."
        case .short:
            return "résumé très court : 5 lignes ou puces au maximum, l'essentiel seulement (sujets traités, décisions, actions). Pas d'introduction ni de conclusion."
        case .free:
            return nil
        }
    }
}

public struct MeetingSummaryRequest: Sendable, Equatable {
    public let transcript: String
    public let instructions: String
    /// Nom de la langue de sortie en toutes lettres (« français »,
    /// « English »), pas un code : c'est ce qu'un modèle de chat comprend
    /// le mieux dans une consigne.
    public let outputLanguage: String
    public let format: ReportFormat

    public init(
        transcript: String, instructions: String, outputLanguage: String, format: ReportFormat = .free
    ) {
        self.transcript = transcript
        self.instructions = instructions
        self.outputLanguage = outputLanguage
        self.format = format
    }
}

public protocol MeetingSummaryProvider: Sendable {
    func summarize(_ request: MeetingSummaryRequest) async throws -> String
}

/// Découpe un transcript trop long pour une seule requête, en coupant de
/// préférence entre deux paragraphes (un paragraphe = un tour de parole),
/// jamais au milieu d'une phrase sauf si un seul paragraphe dépasse la
/// limite à lui seul.
public enum TranscriptChunker {
    public static func split(_ text: String, maxCharacters: Int) -> [String] {
        precondition(maxCharacters > 0)
        guard text.count > maxCharacters else { return [text] }

        var chunks: [String] = []
        var current = ""

        func flush() {
            if !current.isEmpty {
                chunks.append(current)
                current = ""
            }
        }

        for paragraph in text.components(separatedBy: "\n\n") {
            for piece in hardSplit(paragraph, maxCharacters: maxCharacters) {
                let separator = current.isEmpty ? "" : "\n\n"
                if current.count + separator.count + piece.count > maxCharacters {
                    flush()
                    current = piece
                } else {
                    current += separator + piece
                }
            }
        }
        flush()
        return chunks
    }

    private static func hardSplit(_ paragraph: String, maxCharacters: Int) -> [String] {
        guard paragraph.count > maxCharacters else { return [paragraph] }
        var pieces: [String] = []
        var current = ""
        for word in paragraph.split(separator: " ", omittingEmptySubsequences: true) {
            let separator = current.isEmpty ? "" : " "
            if current.count + separator.count + word.count > maxCharacters {
                pieces.append(current)
                current = String(word)
            } else {
                current += separator + word
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }
}
