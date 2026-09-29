/// Format d'encodage de l'audio envoyé à un provider. Un provider a besoin
/// de connaître le format réel des octets qu'il reçoit pour renseigner le
/// nom de fichier / `Content-Type` corrects dans sa requête — les faire
/// diverger des octets réellement envoyés (ex. `.wav` déclaré alors que le
/// fichier est en AAC) peut faire échouer le décodage côté serveur.
public enum AudioFormat: Sendable, Equatable {
    /// PCM non compressé. Simple, sans dépendance à un encodeur, mais lourd
    /// (~1,9 Mo/minute en mono 16 kHz) — coûte du temps d'upload.
    case wav
    /// AAC dans un conteneur MP4 — même contenu utile pour Whisper, environ
    /// 8 à 10x plus léger à 32 kbps mono, donc un upload plus rapide sur
    /// réseau mobile faible.
    case m4a

    public var fileExtension: String {
        switch self {
        case .wav: return "wav"
        case .m4a: return "m4a"
        }
    }

    public var mimeType: String {
        switch self {
        case .wav: return "audio/wav"
        case .m4a: return "audio/m4a"
        }
    }
}
