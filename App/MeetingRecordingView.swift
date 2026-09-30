//
//  MeetingRecordingView.swift
//  Timbre
//

import SwiftUI

/// Écran fonctionnel avant tout (ADR-0005 : l'UI vient après la logique),
/// pas encore passé par la refonte visuelle prévue plus tard.
struct MeetingRecordingView: View {
    @State private var controller = MeetingRecordingController()
    @State private var recordedURL: URL?
    @State private var showTranscript = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text(formattedElapsed)
                .font(.system(size: 48, weight: .medium, design: .monospaced))
                .monospacedDigit()

            if controller.state == .recording {
                Capsule()
                    .fill(Color.red)
                    .frame(width: 16, height: 16)
                    .opacity(0.4 + Double(controller.audioLevel) * 0.6)
            }

            if case .failed(let message) = controller.state {
                Text(message)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            actionButton

            Spacer()
            Spacer()
        }
        .padding()
        .navigationTitle("Enregistrement")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showTranscript) {
            if let recordedURL {
                MeetingTranscriptView(audioURL: recordedURL)
            }
        }
    }

    private var formattedElapsed: String {
        let total = Int(controller.elapsed)
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }

    @ViewBuilder
    private var actionButton: some View {
        switch controller.state {
        case .idle, .failed:
            Button("Démarrer l'enregistrement") {
                Task { await controller.start() }
            }
            .buttonStyle(.borderedProminent)

        case .recording:
            Button("Arrêter") {
                recordedURL = controller.stop()
                showTranscript = recordedURL != nil
            }
            .buttonStyle(.bordered)
            .tint(.red)
        }
    }
}
