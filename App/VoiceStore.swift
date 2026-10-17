//
//  VoiceStore.swift
//  Timbre
//

import Foundation
import TimbreDiarization

/// Stockage local des empreintes vocales (données biométriques, ADR-0007) :
/// profils nommés + empreintes de chaque locuteur de chaque réunion (pour
/// pouvoir nommer une voix après coup). Deux fichiers dans Application
/// Support, chiffrés au repos tant que l'appareil est verrouillé
/// (`.completeFileProtection`) et exclus des sauvegardes — jamais dans
/// l'historique des réunions, qui s'exporte et se partage.
struct VoiceStore {
    private let profilesURL: URL
    private let meetingVoicesURL: URL

    init(directory: URL = VoiceStore.defaultDirectory()) {
        profilesURL = directory.appendingPathComponent("voice-profiles.json")
        meetingVoicesURL = directory.appendingPathComponent("meeting-voices.json")
    }

    private static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let directory = base.appendingPathComponent("Voices", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: - Profils

    func profiles() -> [VoiceProfile] {
        (load([VoiceProfile].self, from: profilesURL) ?? []).sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// Ajoute l'observation au profil du même nom (insensible à la casse et
    /// aux accents) ou en crée un.
    func enroll(name: String, voice: SpeakerVoice) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var all = profiles()
        if let index = all.firstIndex(where: {
            $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            all[index].merge(voice)
        } else {
            all.append(VoiceProfile(name: trimmed, voice: voice))
        }
        write(all, to: profilesURL)
    }

    func renameProfile(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var all = profiles()
        guard let index = all.firstIndex(where: { $0.id == id }) else { return }
        all[index].name = trimmed
        write(all, to: profilesURL)
    }

    func deleteProfile(id: UUID) {
        write(profiles().filter { $0.id != id }, to: profilesURL)
    }

    // MARK: - Empreintes par réunion

    func saveMeetingVoices(meetingID: UUID, voices: [SpeakerID: SpeakerVoice]) {
        guard !voices.isEmpty else { return }
        var all = loadMeetingVoices()
        all[meetingID.uuidString] = Dictionary(uniqueKeysWithValues: voices.map { ($0.key.rawValue, $0.value) })
        write(all, to: meetingVoicesURL)
    }

    func meetingVoice(meetingID: UUID, speaker: SpeakerID) -> SpeakerVoice? {
        loadMeetingVoices()[meetingID.uuidString]?[speaker.rawValue]
    }

    func deleteMeetingVoices(meetingID: UUID) {
        var all = loadMeetingVoices()
        guard all.removeValue(forKey: meetingID.uuidString) != nil else { return }
        write(all, to: meetingVoicesURL)
    }

    /// Droit à l'effacement : profils ET empreintes de toutes les réunions.
    func deleteEverything() {
        try? FileManager.default.removeItem(at: profilesURL)
        try? FileManager.default.removeItem(at: meetingVoicesURL)
    }

    // MARK: - Fichiers

    private func loadMeetingVoices() -> [String: [String: SpeakerVoice]] {
        load([String: [String: SpeakerVoice]].self, from: meetingVoicesURL) ?? [:]
    }

    private func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableURL = url
            try mutableURL.setResourceValues(values)
        } catch {
            // Écriture ou réglage de l'exclusion impossible : la donnée reste
            // celle d'avant (écriture atomique) ; rien à propager à l'UI.
        }
    }
}

/// Réglages de la reconnaissance des voix. Désactivée tant que l'utilisateur
/// n'a pas explicitement consenti (donnée biométrique).
enum VoicePreferences {
    private static let enabledKey = "fr.dafffyl.timbre.voice.enabled"
    private static let consentKey = "fr.dafffyl.timbre.voice.consentDate"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            if newValue { UserDefaults.standard.set(Date(), forKey: consentKey) }
        }
    }

    static var consentDate: Date? {
        UserDefaults.standard.object(forKey: consentKey) as? Date
    }
}

/// Logique « reconnaître / mémoriser », séparée des vues pour être testable.
struct VoiceRecognitionService {
    let store: VoiceStore
    var isEnabled: @Sendable () -> Bool = { VoicePreferences.isEnabled }

    /// Noms à pré-remplir (`SpeakerID.rawValue` → nom) pour une réunion qui
    /// vient d'être transcrite ; mémorise aussi les empreintes de ses
    /// locuteurs pour pouvoir les nommer plus tard.
    func recognize(meetingID: UUID, voices: [SpeakerID: SpeakerVoice]) -> [String: String] {
        guard isEnabled(), !voices.isEmpty else { return [:] }
        store.saveMeetingVoices(meetingID: meetingID, voices: voices)
        let matches = SpeakerMatcher.match(voices: voices, profiles: store.profiles())
        return Dictionary(uniqueKeysWithValues: matches.map { ($0.key.rawValue, $0.value.name) })
    }

    /// L'utilisateur vient de nommer un locuteur : sa voix rejoint (ou crée)
    /// le profil de ce nom.
    func learn(name: String, meetingID: UUID, speaker: SpeakerID) {
        guard isEnabled(), let voice = store.meetingVoice(meetingID: meetingID, speaker: speaker) else { return }
        store.enroll(name: name, voice: voice)
    }
}
