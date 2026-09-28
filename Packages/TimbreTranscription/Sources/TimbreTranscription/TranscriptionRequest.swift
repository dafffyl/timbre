import Foundation

/// `prompt` correspond au champ `prompt` de l'API Whisper — un contexte
/// texte qui améliore la reconnaissance du vocabulaire technique de
/// l'utilisateur (voir le brief produit).
public struct TranscriptionRequest: Sendable {
    public let audio: Data
    public let format: AudioFormat
    public let language: String?
    public let prompt: String?

    public init(audio: Data, format: AudioFormat = .wav, language: String? = nil, prompt: String? = nil) {
        self.audio = audio
        self.format = format
        self.language = language
        self.prompt = prompt
    }
}
