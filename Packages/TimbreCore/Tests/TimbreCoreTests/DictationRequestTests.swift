import Testing
import Foundation

@testable import TimbreCore

@Test func newRequestDefaultsToPending() {
    let request = DictationRequest()
    #expect(request.status == .pending)
    #expect(request.resultText == nil)
}

@Test func roundTripsThroughJSON() throws {
    let original = DictationRequest(status: .ready, resultText: "test")
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(DictationRequest.self, from: data)
    #expect(decoded == original)
}
