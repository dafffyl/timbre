import Foundation

/// Intercepte les requêtes réseau pour les tests — jamais de vrai appel à
/// Groq depuis une suite de tests unitaires.
///
/// `nonisolated(unsafe)` : état global mutable, mais réservé aux tests,
/// jamais utilisé en dehors d'un seul test à la fois (pas de vraie
/// concurrence à protéger ici).
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

/// Boîte mutable pour capturer un résultat depuis le handler synchrone de
/// `MockURLProtocol` — test uniquement : un seul appel réseau par test,
/// toujours awaité avant lecture, jamais de vraie concurrence à protéger.
final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}
