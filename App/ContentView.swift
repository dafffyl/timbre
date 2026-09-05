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

struct ContentView: View {
    @State private var uiState: RecordingUIState = .idle
    @State private var showSettings = false
    @State private var recorder: AVAudioRecorder?
    @State private var recordingURL: URL?

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
                Button("Terminé") { stopRecordingAndTranscribe() }
                    .buttonStyle(.borderedProminent)
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
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wav")
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.record, mode: .default)
                try session.setActive(true)

                let settings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 16_000,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false,
                ]
                let newRecorder = try AVAudioRecorder(url: url, settings: settings)
                newRecorder.record()
                recorder = newRecorder
                recordingURL = url

                guard var request = channel.read(), request.id == requestID else { return }
                request.status = .recording
                request.statusUpdatedAt = Date()
                channel.write(request)
                uiState = .recording
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

    private func stopRecordingAndTranscribe() {
        recorder?.stop()
        recorder = nil

        guard var request = channel.read(), let url = recordingURL else { return }
        let requestID = request.id

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
