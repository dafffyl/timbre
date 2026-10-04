//
//  ContentView.swift
//  Timbre
//

import SwiftUI

struct ContentView: View {
    @State private var showSettings = false
    @State private var showDiarizationSetup = false
    @State private var showHistory = false

    private let controller = DictationController.shared
    private let router = LaunchURLRouter.shared

    var body: some View {
        ZStack {
            AuroraBackground()

            ScrollView {
                VStack(spacing: 28) {
                    header

                    statusCard

                    VStack(spacing: 12) {
                        TimbreMenuRow(
                            icon: "person.wave.2.fill",
                            title: "Transcription de réunion",
                            subtitle: "Enregistrer et distinguer les locuteurs",
                            action: { showDiarizationSetup = true }
                        )
                        TimbreMenuRow(
                            icon: "clock.arrow.circlepath",
                            title: "Réunions transcrites",
                            subtitle: "Historique et export",
                            action: { showHistory = true }
                        )
                        TimbreMenuRow(
                            icon: "gearshape.fill",
                            title: "Réglages",
                            subtitle: "Clé API, vocabulaire, nettoyage",
                            action: { showSettings = true }
                        )
                    }
                }
                .padding(20)
                .padding(.top, 12)
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showDiarizationSetup) {
            DiarizationSetupView()
        }
        .sheet(isPresented: $showHistory) {
            MeetingHistoryView()
        }
        .onAppear { consumePendingURLIfNeeded() }
        .onChange(of: router.pendingURL) { _, _ in consumePendingURLIfNeeded() }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Text("Timbre")
                .font(.timbreDisplay(44))
                .foregroundStyle(Color.timbreTextPrimary)
            Text("Ce qui distingue deux voix sur la même note")
                .font(.timbreCaption())
                .foregroundStyle(Color.timbreTextSecondary)
        }
        .padding(.top, 12)
    }

    @ViewBuilder
    private var statusCard: some View {
        HStack(spacing: 14) {
            statusIcon
            VStack(alignment: .leading, spacing: 3) {
                Text(statusTitle)
                    .font(.timbreTitle(16))
                    .foregroundStyle(Color.timbreTextPrimary)
                if let statusSubtitle {
                    Text(statusSubtitle)
                        .font(.timbreCaption())
                        .foregroundStyle(Color.timbreTextSecondary)
                }
            }
            Spacer()
        }
        .timbreCard()
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch controller.state {
        case .idle:
            Image(systemName: "keyboard.fill")
                .foregroundStyle(Color.timbreTextSecondary)
        case .recording:
            Circle()
                .fill(Color.timbreDanger)
                .frame(width: 10, height: 10)
        case .transcribing:
            ProgressView()
                .tint(Color.timbreViolet)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(LinearGradient.timbreAccent)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.timbreDanger)
        }
    }

    private var statusTitle: String {
        switch controller.state {
        case .idle: "Prêt"
        case .recording: "Enregistrement en cours"
        case .transcribing: "Transcription en cours…"
        case .done: "Terminé"
        case .failed(let message): message
        }
    }

    private var statusSubtitle: String? {
        switch controller.state {
        case .idle: "En attente d'une demande du clavier"
        case .recording, .done: "Contrôle depuis le clavier — reviens dans ton app"
        case .transcribing, .failed: nil
        }
    }

    private func consumePendingURLIfNeeded() {
        guard let url = router.pendingURL else { return }
        router.pendingURL = nil
        guard url.scheme == "timbre" else { return }
        controller.startFromColdWake()
    }
}

#Preview {
    ContentView()
}
