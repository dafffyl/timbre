//
//  VoiceRecognitionServiceTests.swift
//  TimbreTests
//

import Foundation
import Testing
import TimbreDiarization

@testable import Timbre

struct VoiceRecognitionServiceTests {
    private func makeStore() -> (VoiceStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return (VoiceStore(directory: directory), directory)
    }

    private func voice(_ vector: [Float], seconds: TimeInterval = 60) -> SpeakerVoice {
        SpeakerVoice(embedding: VoiceMath.normalized(vector), seconds: seconds)
    }

    private let s1 = SpeakerID(rawValue: "S1")

    @Test func disabledRecognitionStoresAndMatchesNothing() {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = VoiceRecognitionService(store: store, isEnabled: { false })
        let meeting = UUID()

        #expect(service.recognize(meetingID: meeting, voices: [s1: voice([1, 0])]).isEmpty)
        #expect(store.meetingVoice(meetingID: meeting, speaker: s1) == nil)
        service.learn(name: "Sophie", meetingID: meeting, speaker: s1)
        #expect(store.profiles().isEmpty)
    }

    @Test func namingASpeakerThenRecognizingThemInANewMeeting() {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = VoiceRecognitionService(store: store, isEnabled: { true })

        let first = UUID()
        #expect(service.recognize(meetingID: first, voices: [s1: voice([1, 0, 0])]).isEmpty)
        service.learn(name: "Sophie", meetingID: first, speaker: s1)
        #expect(store.profiles().map(\.name) == ["Sophie"])

        let second = UUID()
        let names = service.recognize(meetingID: second, voices: [SpeakerID(rawValue: "S7"): voice([0.97, 0.05, 0])])
        #expect(names == ["S7": "Sophie"])
    }

    @Test func enrollingSameNameMergesInsteadOfDuplicating() {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        store.enroll(name: "Élodie", voice: voice([1, 0]))
        store.enroll(name: "elodie", voice: voice([0.9, 0.1]))
        #expect(store.profiles().count == 1)
    }

    @Test func deleteEverythingErasesProfilesAndMeetingVoices() {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let meeting = UUID()
        store.saveMeetingVoices(meetingID: meeting, voices: [s1: voice([1, 0])])
        store.enroll(name: "Sophie", voice: voice([1, 0]))

        store.deleteEverything()

        #expect(store.profiles().isEmpty)
        #expect(store.meetingVoice(meetingID: meeting, speaker: s1) == nil)
    }

    @Test func deletingAMeetingRemovesItsVoices() {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        let meeting = UUID()
        store.saveMeetingVoices(meetingID: meeting, voices: [s1: voice([1, 0])])
        store.deleteMeetingVoices(meetingID: meeting)
        #expect(store.meetingVoice(meetingID: meeting, speaker: s1) == nil)
    }
}
