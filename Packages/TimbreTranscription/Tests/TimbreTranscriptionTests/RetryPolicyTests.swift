import Testing
import Foundation

@testable import TimbreTranscription

private actor Counter {
    private(set) var value = 0
    func increment() -> Int {
        value += 1
        return value
    }
}

@Test func succeedsOnFirstAttemptWithoutRetrying() async throws {
    let counter = Counter()
    let result = try await withRetry(policy: RetryPolicy(maxAttempts: 3, baseDelay: 0.01)) {
        await counter.increment()
    }
    #expect(result == 1)
}

@Test func retriesTransientFailureThenSucceeds() async throws {
    let counter = Counter()
    let result = try await withRetry(policy: RetryPolicy(maxAttempts: 3, baseDelay: 0.01)) {
        let attempt = await counter.increment()
        if attempt < 3 {
            throw TranscriptionError.network("temporaire")
        }
        return attempt
    }
    #expect(result == 3)
}

@Test func stopsImmediatelyWhenShouldRetryReturnsFalse() async throws {
    let counter = Counter()

    await #expect(throws: TranscriptionError.missingAPIKey) {
        try await withRetry(
            policy: RetryPolicy(maxAttempts: 5, baseDelay: 0.01),
            shouldRetry: { _ in false }
        ) {
            _ = await counter.increment()
            throw TranscriptionError.missingAPIKey
        }
    }

    #expect(await counter.value == 1)
}

@Test func throwsLastErrorAfterExhaustingAttempts() async throws {
    let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0.01)

    await #expect(throws: TranscriptionError.network("persistant")) {
        try await withRetry(policy: policy) {
            throw TranscriptionError.network("persistant")
        }
    }
}
