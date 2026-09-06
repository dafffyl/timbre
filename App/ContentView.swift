//
//  ContentView.swift
//  Timbre
//

import SwiftUI

struct ContentView: View {
    @State private var showSettings = false

    private let controller = DictationController.shared
    private let router = LaunchURLRouter.shared

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
        switch controller.state {
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
        controller.startFromColdWake()
    }
}

#Preview {
    ContentView()
}
