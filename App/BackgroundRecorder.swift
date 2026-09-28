//
//  BackgroundRecorder.swift
//  Timbre
//

@preconcurrency import AVFoundation
import os

/// Enregistre via `AVAudioEngine` plutôt que `AVAudioRecorder` — seule façon
/// de garder le contrôle programmatique nécessaire pour lire l'App Group à
/// intervalles réguliers pendant l'enregistrement (voir `DictationController`),
/// tout en profitant de la survie en arrière-plan validée par ADR-0002.
///
/// `@unchecked Sendable` : `converter`/`targetFormat` sont écrits une seule
/// fois dans `start()`, avant l'installation du tap, puis seulement lus —
/// jamais mutés — depuis le thread audio temps réel du tap. `audioFileBox`
/// et `level`, eux, sont mutés après coup (reprise à chaud, fenêtre de
/// grâce) et protégés individuellement par un verrou. `recordedURL`/
/// `isEngineRunning` ne sont touchés que depuis l'acteur principal.
final class BackgroundRecorder: @unchecked Sendable {
    enum RecordingError: Error {
        case formatUnavailable
    }

    private let engine = AVAudioEngine()

    /// `nonisolated(unsafe)` : écrits une seule fois dans `start()`, avant
    /// l'installation du tap, puis seulement lus — jamais mutés — depuis le
    /// thread audio temps réel. L'invariant est le même que celui déjà
    /// documenté pour `@unchecked Sendable` au niveau de la classe.
    nonisolated(unsafe) private var converter: AVAudioConverter?
    nonisolated(unsafe) private var targetFormat: AVAudioFormat?

    private(set) var recordedURL: URL?
    private(set) var isEngineRunning = false

    private let audioFileBox = OSAllocatedUnfairLock<AVAudioFile?>(initialState: nil)
    private let level = OSAllocatedUnfairLock<Float>(initialState: 0)

    /// Niveau audio courant, normalisé 0...1. Sûr à lire depuis n'importe
    /// quel thread.
    var currentLevel: Float {
        level.withLock { $0 }
    }

    /// Démarrage à froid : active la session, lance le moteur, installe le
    /// tap. Point d'entrée unique — `resumeRecording()` ne repasse jamais
    /// par ici, elle réutilise le moteur déjà lancé.
    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        // Float32 non-interleaved : c'est le format canonique qu'`AVAudioFile`
        // attend en entrée de `write(from:)` quand le fichier de destination
        // est compressé (AAC) — le convertisseur interne (`ExtAudioFile`) qui
        // encode à l'écriture n'accepte pas n'importe quel agencement PCM en
        // amont. Le passage à Int16 se fait uniquement dans l'encodeur AAC,
        // pas ici.
        guard
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            ),
            let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        else {
            throw RecordingError.formatUnavailable
        }
        self.targetFormat = targetFormat
        self.converter = converter

        try openNewFile()

        inputNode.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [self] buffer, _ in
            process(buffer: buffer)
        }
        engine.prepare()
        try engine.start()
        isEngineRunning = true
    }

    /// Reprise "à chaud" pendant la fenêtre de grâce (voir
    /// `DictationController`) : le moteur tourne déjà, on rouvre juste un
    /// nouveau fichier — aucun besoin de retoucher à la session ni au tap.
    func resumeRecording() throws {
        try openNewFile()
    }

    /// Fin de dictée sans tout couper : ferme le fichier courant mais
    /// laisse le moteur (et la session) actifs, pour permettre une reprise
    /// immédiate sans bascule visible si une nouvelle dictée arrive vite.
    func beginGracePeriod() {
        audioFileBox.withLock { $0 = nil }
        recordedURL = nil
    }

    /// Arrêt complet : plus de reprise possible sans repasser par `start()`.
    func stop() {
        isEngineRunning = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFileBox.withLock { $0 = nil }
        recordedURL = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Écrit directement en AAC (conteneur `.m4a`) plutôt qu'en PCM brut :
    /// même contenu utile pour Whisper, ~8-10x plus léger à 32 kbps mono
    /// 16 kHz — donc un upload plus rapide vers Groq, en particulier sur
    /// réseau mobile faible. `AVAudioFile` encode lui-même à l'écriture
    /// (`ExtAudioFile` sous le capot) à partir du buffer Float32
    /// non-entrelacé produit par `process(buffer:)`.
    private func openNewFile() throws {
        guard let targetFormat else { throw RecordingError.formatUnavailable }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: targetFormat.sampleRate,
            AVNumberOfChannelsKey: targetFormat.channelCount,
            AVEncoderBitRateKey: 32_000,
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        audioFileBox.withLock { $0 = file }
        recordedURL = url
    }

    /// Tourne sur le thread temps réel du moteur audio : uniquement
    /// conversion PCM + écriture disque ici, jamais de lecture de l'App
    /// Group (`UserDefaults(suiteName:)`) — ce polling-là vit dans
    /// `DictationController`, sur l'acteur principal, à un rythme bien
    /// plus lent.
    /// `nonisolated` explicite : ce module force l'isolation `MainActor` par
    /// défaut, mais cette méthode tourne réellement sur le thread temps réel
    /// du tap audio — la marquer clarifie l'intention plutôt que de laisser
    /// le vérificateur de concurrence deviner.
    nonisolated private func process(buffer: AVAudioPCMBuffer) {
        level.withLock { $0 = Self.computeLevel(from: buffer) }

        guard let converter, let targetFormat else { return }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var conversionError: NSError?
        converter.convert(to: converted, error: &conversionError) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard conversionError == nil else { return }

        audioFileBox.withLock { file in
            try? file?.write(from: converted)
        }
    }

    /// RMS en dB plutôt qu'amplitude linéaire : l'oreille (et donc une onde
    /// visuellement crédible) perçoit le volume de façon logarithmique — une
    /// échelle linéaire écraserait tout sauf les pics les plus forts. -50 dB
    /// (silence de fond typique d'un micro de téléphone) est calé à 0, 0 dB
    /// (saturation) à 1.
    nonisolated private static func computeLevel(from buffer: AVAudioPCMBuffer) -> Float {
        guard let channelData = buffer.floatChannelData?[0] else { return 0 }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return 0 }

        var sum: Float = 0
        for index in 0..<frameLength {
            let sample = channelData[index]
            sum += sample * sample
        }
        let rms = (sum / Float(frameLength)).squareRoot()
        let decibels = 20 * log10(max(rms, 1e-6))
        let normalized = (decibels + 50) / 50
        return min(max(normalized, 0), 1)
    }
}
