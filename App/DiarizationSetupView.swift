//
//  DiarizationSetupView.swift
//  Timbre
//

import SwiftUI
import TimbreDiarization

/// Écran de provisionnement des modèles de diarisation.
///
/// Ne construit PAS la fonctionnalité réunion elle-même (enregistrement,
/// transcription, affichage du transcript par locuteur) — seulement le
/// passage obligé avant : s'assurer que le modèle est prêt sur l'appareil.
struct DiarizationSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = DiarizationSetupViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()

                VStack(spacing: 24) {
                    Spacer()

                    iconBadge

                    VStack(spacing: 10) {
                        Text(title)
                            .font(.timbreTitle(22))
                            .foregroundStyle(Color.timbreTextPrimary)
                            .multilineTextAlignment(.center)

                        Text(message)
                            .font(.timbreBody(15))
                            .foregroundStyle(Color.timbreTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 12)

                    if viewModel.isChecking {
                        ProgressView()
                            .tint(Color.timbreViolet)
                            .padding(.top, 4)
                    } else {
                        actionButton
                    }

                    Spacer()
                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("Transcription de réunion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await viewModel.refresh() }
    }

    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(iconColor.opacity(0.16))
                .frame(width: 96, height: 96)
            Image(systemName: iconName)
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(iconColor)
        }
    }

    private var iconName: String {
        switch viewModel.state {
        case .ready: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        case .needsWiFi: "wifi.slash"
        case .needsConsent, nil: "arrow.down.circle"
        }
    }

    private var iconColor: AnyShapeStyle {
        switch viewModel.state {
        case .ready: AnyShapeStyle(LinearGradient.timbreAccent)
        case .failed: AnyShapeStyle(Color.timbreDanger)
        case .needsWiFi: AnyShapeStyle(Color.timbreCoral)
        case .needsConsent, nil: AnyShapeStyle(Color.timbreViolet)
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
            .buttonStyle(TimbrePrimaryButtonStyle())

        case .needsWiFi, .failed:
            Button("Réessayer") {
                Task { await viewModel.refresh() }
            }
            .buttonStyle(TimbreSecondaryButtonStyle())

        case .ready:
            NavigationLink("Démarrer une réunion") {
                MeetingRecordingView()
            }
            .buttonStyle(TimbrePrimaryButtonStyle())

        case nil:
            EmptyView()
        }
    }
}

#Preview {
    DiarizationSetupView()
}
