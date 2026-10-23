//
//  AudioSessionUsageTests.swift
//  TimbreTests
//

import Testing

@testable import Timbre

struct AudioSessionUsageTests {
    @Test func onlyTheLastRecorderDeactivatesTheSession() {
        let usage = AudioSessionUsage()
        usage.acquire()  // dictée (fenêtre de grâce)
        usage.acquire()  // réunion
        #expect(usage.release() == false)  // fin de la grâce : la réunion continue
        #expect(usage.release() == true)  // fin de la réunion : on désactive
    }

    @Test func extraReleaseNeverGoesNegative() {
        let usage = AudioSessionUsage()
        #expect(usage.release() == true)
        usage.acquire()
        #expect(usage.activeCount == 1)
        #expect(usage.release() == true)
        #expect(usage.activeCount == 0)
    }
}
