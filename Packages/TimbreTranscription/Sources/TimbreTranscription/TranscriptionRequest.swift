import Foundation

/// `prompt` correspond au champ `prompt` de l'API Whisper — un contexte
/// texte qui améliore la reconnaissance du vocabulaire technique de
/// l'utilisateur (voir le brief produit).
public struct TranscriptionRequest: Sendable {
    public let audio: Data
    public let language: String?
    public let prompt: String?

    public init(audio: Data, language: String? = nil, prompt: String? = nil) {
        self.audio = audio
        self.language = language
        self.prompt = prompt
    }
}
