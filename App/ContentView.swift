//
//  ContentView.swift
//  Timbre
//

import SwiftUI
import TimbreCore
import TimbreSecurity

/// Phase 2 — cycle à vide : aucune vraie transcription, juste un délai
/// simulant le temps de traitement, pour valider le canal et les états
/// dégradés avant de brancher Groq/FluidAudio en Phase 3+.
struct ContentView: View {
    @State private var status = "Prêt — en attente d'une demande du clavier."
    private let router = LaunchURLRouter.shared

    private let channel = DictationChannel()
    private let dummyResultText = "Ceci est un texte de test inséré automatiquement depuis Timbre."

    var body: some View {
        VStack(spacing: 16) {
            Text("Timbre")
                .font(.largeTitle)
            Text(status)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .onAppear { consumePendingURLIfNeeded() }
        .onChange(of: router.pendingURL) { _, _ in consumePendingURLIfNeeded() }
    }

    private func consumePendingURLIfNeeded() {
        guard let url = router.pendingURL else { return }
        router.pendingURL = nil
        guard url.scheme == "timbre" else { return }
        simulateDictation()
    }

    private func simulateDictation() {
        guard var request = channel.read(), request.status == .pending else { return }

        status = "Dictée en cours (factice)…"

        Task {
            try? await Task.sleep(for: .seconds(2))

            request.status = .ready
            request.resultText = dummyResultText
            channel.write(request)

            await MainActor.run {
                status = "Terminé — reviens dans ton app."
            }
        }
    }
}

#Preview {
    ContentView()
}
