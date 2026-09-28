/// `text` est le résultat brut d'un `TranscriptionProvider` — cette étape ne
/// réenregistre jamais d'audio, elle ne fait que reformuler du texte déjà
/// transcrit. `language` guide le modèle sur la langue de sortie attendue
/// (identique à celle passée à la transcription, pas redétectée ici).
public struct TextCleanupRequest: Sendable {
    public let text: String
    public let language: String?

    public init(text: String, language: String? = nil) {
        self.text = text
        self.language = language
    }
}
