//
//  OnboardingView.swift
//  Timbre
//

import SwiftUI
import TimbreSecurity

/// Checklist de première configuration, affichée sur l'accueil tant qu'elle
/// n'est pas complète — à la place du statut « Prêt » qui s'affichait même
/// sans clé API ni clavier activé.
struct OnboardingChecklistCard: View {
    let progress: OnboardingProgress
    var openSettings: () -> Void
    var openAPIKeySettings: () -> Void
    var confirmFullAccess: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Configure Timbre")
                    .font(.timbreTitle(18))
                    .foregroundStyle(Color.timbreTextPrimary)
                Text("\(progress.completedCount) étape\(progress.completedCount > 1 ? "s" : "") sur 4")
                    .font(.timbreCaption())
                    .foregroundStyle(Color.timbreTextSecondary)
            }

            step(
                done: progress.hasAPIKey,
                title: "Ajoute ta clé API Groq",
                detail: "Nécessaire pour transcrire. Gratuite sur console.groq.com.",
                actionTitle: "Ouvrir les réglages",
                action: openAPIKeySettings
            )
            step(
                done: progress.keyboardEnabled,
                title: "Active le clavier Timbre",
                detail: "Réglages › Timbre › Claviers, active « Timbre ».",
                actionTitle: "Ouvrir Réglages iOS",
                action: openSettings
            )
            step(
                done: progress.fullAccessConfirmed,
                title: "Autorise l'accès complet",
                detail: "Dans le même écran, active « Autoriser l'accès complet » : sans lui le clavier ne peut pas joindre l'app. Timbre ne lit jamais ce que tu tapes.",
                actionTitle: "C'est fait",
                action: confirmFullAccess
            )
            step(
                done: progress.firstDictationDone,
                title: "Fais une première dictée",
                detail: "Dans n'importe quelle app, maintiens 🌐 pour choisir Timbre, puis touche « Dicter ». Reviens ensuite à ton app manuellement.",
                actionTitle: nil,
                action: {}
            )
        }
        .timbreCard()
    }

    @ViewBuilder
    private func step(
        done: Bool,
        title: String,
        detail: String,
        actionTitle: String?,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .foregroundStyle(done ? AnyShapeStyle(LinearGradient.timbreAccent) : AnyShapeStyle(Color.timbreTextSecondary))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.timbreTitle(15))
                    .foregroundStyle(Color.timbreTextPrimary)
                if !done {
                    Text(detail)
                        .font(.timbreCaption())
                        .foregroundStyle(Color.timbreTextSecondary)
                    if let actionTitle {
                        Button(actionTitle, action: action)
                            .font(.timbreCaption())
                            .foregroundStyle(Color.timbreViolet)
                            .padding(.top, 2)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(done ? "\(title), terminé" : title)
    }
}
