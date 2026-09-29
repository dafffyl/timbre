public struct TextCleanupResult: Sendable, Equatable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}
