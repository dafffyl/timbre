//
//  OnboardingTests.swift
//  TimbreTests
//

import Testing

@testable import Timbre

struct OnboardingTests {
    @Test func keyboardDetectedFromEnabledKeyboards() {
        #expect(OnboardingPreferences.isKeyboardEnabled(keyboards: ["fr_FR@sw=AZERTY", "fr.dafffyl.timbre.keyboard"]))
        #expect(!OnboardingPreferences.isKeyboardEnabled(keyboards: ["fr_FR@sw=AZERTY"]))
        #expect(!OnboardingPreferences.isKeyboardEnabled(keyboards: nil))
    }

    @Test func progressCountsCompletedSteps() {
        var progress = OnboardingProgress(
            hasAPIKey: true, keyboardEnabled: false, fullAccessConfirmed: false, firstDictationDone: false)
        #expect(progress.completedCount == 1)
        #expect(!progress.isComplete)

        progress.keyboardEnabled = true
        progress.fullAccessConfirmed = true
        progress.firstDictationDone = true
        #expect(progress.completedCount == 4)
        #expect(progress.isComplete)
    }
}
