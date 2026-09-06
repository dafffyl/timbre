//
//  ContentView.swift
//  Timbre
//

import SwiftUI
import AVFoundation
import TimbreCore
import TimbreSecurity
import TimbreTranscription

private enum RecordingUIState: Equatable {
    case idle
    case recording
    case transcribing
    case done
    case failed(String)
}

/// Enregistre via `AVAudioEngine` plutôt que `AVAudioRecorder` — seule façon
/// de garder le contrôle programmatique nécessaire pour lire l'App Group à
/// intervalles réguliers pendant l'enregistrement (voir `ContentView`), tout
/// en profitant de la survie en arrière-plan validée par ADR-0002.
///
/// `@unchecked Sendable` : `audioFile`/`converter`/`targetFormat` sont écrits
/// une seule fois dans `start()`, avant l'installation du tap, puis seulement
/// lus — jamais mutés — depuis le thread audio temps réel du tap. `recordedURL`
/// n'est lu depuis l'acteur principal qu'après `stop()`, une fois le tap retiré.
final class BackgroundRecorder: @unchecked Sendable {
    enum RecordingError: Error {
        case formatUnavailable
    }

    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private(set) var recordedURL: URL?

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 16_000,
                channels: 1,
                interleaved: true
            ),
            let converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        else {
            throw RecordingError.formatUnavailable
        }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
        let file = try AVAudioFile(
            forWriting: url,
            settings: targetFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )

        self.targetFormat = targetFormat
        self.converter = converter
        self.audioFile = file
        self.recordedURL = url

        inputNode.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [self] buffer, _ in
            process(buffer: buffer)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        audioFile = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Tourne sur le thread temps réel du moteur audio : uniquement
    /// conversion PCM + écriture disque ici, jamais de lecture de l'App
    /// Group (`UserDefaults(suiteName:)`) — ce polling-là vit dans
    /// `ContentView`, sur l'acteur principal, à un rythme bien plus lent.
    private func process(buffer: AVAudioPCMBuffer) {
        guard let converter, let targetFormat, let audioFile else { return }

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
        try? audioFile.write(from: converted)
    }
}

struct ContentView: View {
    /// Filet de sécurité : au-delà, l'app termine et transcrit d'elle-même,
    /// même sans signal du clavier — voir Phase 3.5 item 2.
    private static let maxRecordingDuration: TimeInterval = 180

    @State private var uiState: RecordingUIState = .idle
    @State private var showSettings = false
    @State private var recorder = BackgroundRecorder()
    @State private var pollTimer: Timer?
    @State private var recordingStartedAt: Date?

    private let router = LaunchURLRouter.shared
    private let channel = DictationChannel()

    var body: some View {
        VStack(spacing: 20) {
            Text("Timbre")
                .font(.largeTitle)

            statusView

            Button("Réglages") { showSettings = true }
                .font(.footnote)
        }
        .padding()
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear { consumePendingURLIfNeeded() }
        .onChange(of: router.pendingURL) { _, _ in consumePendingURLIfNeeded() }
    }

    @ViewBuilder
    private var statusView: some View {
        switch uiState {
        case .idle:
            Text("Prêt — en attente d'une demande du clavier.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

        case .recording:
            VStack(spacing: 12) {
                Text("🔴 Enregistrement en cours")
                Text("Contrôle depuis le clavier — reviens dans ton app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

        case .transcribing:
            VStack(spacing: 12) {
                ProgressView()
                Text("Transcription en cours…")
                    .foregroundStyle(.secondary)
            }

        case .done:
            Text("Terminé — reviens dans ton app.")
                .foregroundStyle(.secondary)

        case .failed(let message):
            Text(message)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }

    private func consumePendingURLIfNeeded() {
        guard let url = router.pendingURL else { return }
        router.pendingURL = nil
        guard url.scheme == "timbre" else { return }
        startRecording()
    }

    private func startRecording() {
        guard let initialRequest = channel.read(), initialRequest.status == .pending else { return }
        let requestID = initialRequest.id

        Task { @MainActor in
            let allowed = await requestMicrophonePermission()
            guard allowed else {
                markFailed(requestID: requestID, message: "Accès micro refusé — active-le dans Réglages.")
                return
            }

            do {
                try recorder.start()

                guard var request = channel.read(), request.id == requestID else {
                    recorder.stop()
                    return
                }
                request.status = .recording
                request.statusUpdatedAt = Date()
                channel.write(request)
                uiState = .recording
                recordingStartedAt = Date()
                startPolling(requestID: requestID)
            } catch {
                markFailed(requestID: requestID, message: "Impossible de démarrer l'enregistrement.")
            }
        }
    }

    private func requestMicrophonePermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    /// Seule source de vérité pendant l'enregistrement : le clavier ne pousse
    /// plus de bouton "Terminé" côté app (ADR-0002, Phase 3.5 item 2) — tout
    /// passe par `stopRequested` dans l'App Group, plus ce filet de sécurité
    /// de durée. Rythme volontairement plus lent que le tap audio (qui, lui,
    /// ne doit jamais toucher à l'App Group — voir `BackgroundRecorder`).
    private func startPolling(requestID: UUID) {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in
            pollDuringRecording(requestID: requestID)
        }
    }

    private func pollDuringRecording(requestID: UUID) {
        guard let request = channel.read(), request.id == requestID else {
            // Le clavier a vidé le canal (`cancel()`) ou une autre requête
            // l'a remplacé : on interprète ça comme une annulation.
            cancelRecording()
            return
        }

        if request.stopRequested {
            stopRecordingAndTranscribe(requestID: requestID)
            return
        }

        if let startedAt = recordingStartedAt,
            Date().timeIntervalSince(startedAt) > Self.maxRecordingDuration
        {
            stopRecordingAndTranscribe(requestID: requestID)
        }
    }

    private func cancelRecording() {
        pollTimer?.invalidate()
        pollTimer = nil
        recorder.stop()
        if let url = recorder.recordedURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingStartedAt = nil
        uiState = .idle
    }

    private func stopRecordingAndTranscribe(requestID: UUID) {
        pollTimer?.invalidate()
        pollTimer = nil
        recorder.stop()
        recordingStartedAt = nil

        guard let url = recorder.recordedURL, var request = channel.read(), request.id == requestID else { return }

        request.status = .transcribing
        request.statusUpdatedAt = Date()
        channel.write(request)
        uiState = .transcribing

        Task { @MainActor in
            do {
                let audioData = try Data(contentsOf: url)
                try? FileManager.default.removeItem(at: url)

                let apiKeyStore = APIKeyStore()
                let provider = GroqProvider(apiKey: { (try? apiKeyStore.load()) ?? nil })
                let result = try await provider.transcribe(TranscriptionRequest(audio: audioData, language: "fr"))

                guard var ready = channel.read(), ready.id == requestID else { return }
                ready.status = .ready
                ready.statusUpdatedAt = Date()
                ready.resultText = result.text
                channel.write(ready)
                uiState = .done
            } catch {
                markFailed(requestID: requestID, message: Self.userMessage(for: error))
            }
        }
    }

    private func markFailed(requestID: UUID, message: String) {
        if var request = channel.read(), request.id == requestID {
            request.status = .failed
            request.statusUpdatedAt = Date()
            request.errorMessage = message
            channel.write(request)
        }
        uiState = .failed(message)
    }

    private static func userMessage(for error: Error) -> String {
        guard let error = error as? TranscriptionError else {
            return "Erreur inattendue."
        }
        switch error {
        case .missingAPIKey:
            return "Clé API Groq manquante — configure-la dans les réglages."
        case .fileTooLarge:
            return "Enregistrement trop long pour Groq (25 Mo max)."
        case .network:
            return "Problème réseau — vérifie ta connexion."
        case .rateLimited:
            return "Trop de requêtes envoyées à Groq — réessaie dans un instant."
        case .server(let statusCode, _):
            return "Erreur Groq (code \(statusCode))."
        case .decoding, .invalidResponse:
            return "Réponse inattendue de Groq."
        case .cancelled:
            return "Annulé."
        }
    }
}

#Preview {
    ContentView()
}
