/// Ce qu'un provider sait faire — permet à l'appelant de s'adapter (ex. ne
/// pas tenter l'alignement diarisation si `supportsNativeDiarization` est
/// déjà `true`) sans connaître le provider concret.
public struct ProviderCapabilities: Sendable, Equatable {
    public let supportsNativeDiarization: Bool
    public let supportsStreaming: Bool
    public let wordTimestamps: Bool
    public let maxFileSizeBytes: Int?

    public init(
        supportsNativeDiarization: Bool,
        supportsStreaming: Bool,
        wordTimestamps: Bool,
        maxFileSizeBytes: Int? = nil
    ) {
        self.supportsNativeDiarization = supportsNativeDiarization
        self.supportsStreaming = supportsStreaming
        self.wordTimestamps = wordTimestamps
        self.maxFileSizeBytes = maxFileSizeBytes
    }
}
