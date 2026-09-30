//
//  DiarizationSetupView.swift
//  Timbre
//

import SwiftUI
import TimbreDiarization

/// Écran de provisionnement des modèles de diarisation — vue fonctionnelle
/// avant tout (ADR-0004 : l'UI vient après la logique), pas encore passée
/// par la refonte visuelle prévue plus tard pour le reste de l'app.
///
/// Ne construit PAS la fonctionnalité réunion elle-même (enregistrement,
/// transcription, affichage du transcript par locuteur) — seulement le
/// passage obligé avant : s'assurer que le modèle est prêt sur l'appareil.
struct DiarizationSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = DiarizationSetupViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                Image(systemName: iconName)
                    .font(.system(size: 48))
                    .foregroundStyle(iconColor)

                Text(title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                Text(message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if viewModel.isChecking {
                    ProgressView()
                        .padding(.top, 4)
                } else {
                    actionButton
                }

                Spacer()
                Spacer()
            }
            .padding()
            .navigationTitle("Transcription de réunion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .task { await viewModel.refresh() }
    }

    private var iconName: String {
        switch viewModel.state {
        case .ready: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .needsWiFi: "wifi.slash"
        case .needsConsent, nil: "arrow.down.circle"
        }
    }

    private var iconColor: Color {
        switch viewModel.state {
        case .ready: .green
        case .failed: .red
        case .needsWiFi: .orange
        case .needsConsent, nil: .accentColor
        }
    }

    private var title: String {
        switch viewModel.state {
        case nil: "Vérification…"
        case .ready: "Prêt"
        case .needsConsent: "Télécharger le modèle de diarisation"
        case .needsWiFi: "Connexion Wi-Fi requise"
        case .failed: "Échec du téléchargement"
        }
    }

    private var message: String {
        switch viewModel.state {
        case nil:
            ""
        case .ready:
            "Le modèle de reconnaissance des locuteurs est prêt sur cet appareil."
        case .needsConsent:
            "La distinction des locuteurs fonctionne entièrement sur ton téléphone, mais nécessite un téléchargement unique d'environ 500 Mo. Toujours sur Wi-Fi, jamais sur données cellulaires."
        case .needsWiFi:
            "Le téléchargement du modèle (~500 Mo) nécessite une connexion Wi-Fi — connecte-toi puis réessaie."
        case .failed(let reason):
            reason
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        switch viewModel.state {
        case .needsConsent:
            Button("Télécharger sur Wi-Fi (~500 Mo)") {
                Task { await viewModel.grantConsent() }
            }
            .buttonStyle(.borderedProminent)

        case .needsWiFi, .failed:
            Button("Réessayer") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(.bordered)

        case .ready:
            NavigationLink("Démarrer une réunion") {
                MeetingRecordingView()
            }
            .buttonStyle(.borderedProminent)

        case nil:
            EmptyView()
        }
    }
}

#Preview {
    DiarizationSetupView()
}
