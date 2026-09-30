//
//  MeetingRecordingView.swift
//  Timbre
//

import SwiftUI

struct MeetingRecordingView: View {
    @State private var controller = MeetingRecordingController()
    @State private var recordedURL: URL?
    @State private var showTranscript = false
    @State private var levelHistory: [Float] = []

    var body: some View {
        ZStack {
            AuroraBackground()

            VStack(spacing: 32) {
                Spacer()

                Text(formattedElapsed)
                    .font(.system(size: 56, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.timbreTextPrimary)

                WaveformBars(levels: levelHistory, barCount: 32, maxHeight: 56)
                    .opacity(controller.state == .recording ? 1 : 0.25)

                if case .failed(let message) = controller.state {
                    Text(message)
                        .font(.timbreBody(15))
                        .foregroundStyle(Color.timbreDanger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Spacer()

                recordButton

                Text(controller.state == .recording ? "Toucher pour arrêter" : "Toucher pour démarrer")
                    .font(.timbreCaption())
                    .foregroundStyle(Color.timbreTextSecondary)

                Spacer()
            }
            .padding(24)
        }
        .preferredColorScheme(.dark)
        .navigationTitle("Enregistrement")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $showTranscript) {
            if let recordedURL {
                MeetingTranscriptView(audioURL: recordedURL)
            }
        }
        .onChange(of: controller.audioLevel) { _, newLevel in
            levelHistory.append(newLevel)
            if levelHistory.count > 32 {
                levelHistory.removeFirst()
            }
        }
    }

    private var formattedElapsed: String {
        let total = Int(controller.elapsed)
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }

    private var recordButton: some View {
        Button {
            switch controller.state {
            case .idle, .failed:
                Task { await controller.start() }
            case .recording:
                recordedURL = controller.stop()
                showTranscript = recordedURL != nil
            }
        } label: {
            ZStack {
                Circle()
                    .fill(controller.state == .recording ? AnyShapeStyle(Color.timbreDanger) : AnyShapeStyle(LinearGradient.timbreAccent))
                    .frame(width: 88, height: 88)
                    .shadow(
                        color: (controller.state == .recording ? Color.timbreDanger : Color.timbreViolet).opacity(0.5),
                        radius: 20,
                        y: 8
                    )

                if controller.state == .recording {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.white)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
