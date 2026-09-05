/// Identifie un provider sans registre central fermé (un `enum` obligerait à
/// modifier ce package à chaque nouveau provider).
public struct ProviderIdentifier: Sendable, Hashable, RawRepresentable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let groq = ProviderIdentifier(rawValue: "groq")
}
