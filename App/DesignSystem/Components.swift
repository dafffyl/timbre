//
//  Components.swift
//  Timbre
//

import SwiftUI

/// Fond signature de l'app — dégradé sombre + deux halos flous (violet,
/// corail), écho direct de l'icône. Un seul point d'implémentation pour que
/// tous les écrans partagent exactement le même fond plutôt que des
/// variations proches mais divergentes.
struct AuroraBackground: View {
    var body: some View {
        ZStack {
            LinearGradient.timbreBackground

            Circle()
                .fill(Color.timbreViolet.opacity(0.32))
                .frame(width: 380, height: 380)
                .blur(radius: 110)
                .offset(x: -130, y: -280)

            Circle()
                .fill(Color.timbreCoral.opacity(0.26))
                .frame(width: 340, height: 340)
                .blur(radius: 120)
                .offset(x: 150, y: 260)
        }
        .ignoresSafeArea()
    }
}

/// Carte translucide (`.ultraThinMaterial` + léger voile de surface, bordure
/// 1px à 8% blanc) — le composant de base de presque tous les écrans.
struct TimbreCard: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.timbreSurface.opacity(0.35))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            )
    }
}

extension View {
    func timbreCard(padding: CGFloat = 16) -> some View {
        modifier(TimbreCard(padding: padding))
    }
}

/// Bouton principal — capsule dégradé violet→corail, avec un léger effet
/// d'enfoncement au tap plutôt qu'un simple changement de couleur.
struct TimbrePrimaryButtonStyle: ButtonStyle {
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.timbreLabel(17))
            .foregroundStyle(.white)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .background(
                isDestructive
                    ? AnyShapeStyle(Color.timbreDanger)
                    : AnyShapeStyle(LinearGradient.timbreAccent)
            )
            .opacity(configuration.isPressed ? 0.85 : 1)
            .clipShape(Capsule())
            .shadow(
                color: (isDestructive ? Color.timbreDanger : Color.timbreViolet).opacity(0.35),
                radius: configuration.isPressed ? 6 : 14,
                y: 6
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Bouton secondaire — capsule translucide, pour les actions qui ne doivent
/// pas rivaliser visuellement avec l'action principale d'un écran.
struct TimbreSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.timbreLabel(16))
            .foregroundStyle(Color.timbreTextPrimary)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(Color.white.opacity(configuration.isPressed ? 0.14 : 0.07))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.12), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Ligne de menu façon carte (icône dégradé + titre + sous-titre + chevron)
/// — remplace les `Button` texte bleu par défaut de l'écran d'accueil.
struct TimbreMenuRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient.timbreAccent.opacity(0.18))
                        .frame(width: 48, height: 48)
                    Image(systemName: icon)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(LinearGradient.timbreAccent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.timbreTitle(17))
                        .foregroundStyle(Color.timbreTextPrimary)
                    Text(subtitle)
                        .font(.timbreCaption())
                        .foregroundStyle(Color.timbreTextSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.timbreTextSecondary)
            }
        }
        .buttonStyle(.plain)
        .timbreCard()
    }
}

/// Barres de niveau audio partagées — utilisées par le clavier (onde live)
/// et l'écran d'enregistrement de réunion, pour ne jamais avoir deux styles
/// de "waveform" différents dans la même app.
struct WaveformBars: View {
    let levels: [Float]
    var barCount = 24
    var maxHeight: CGFloat = 40

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(LinearGradient.timbreAccent)
                    .frame(width: 4, height: height(at: index))
            }
        }
        .frame(height: maxHeight)
        .animation(.easeOut(duration: 0.08), value: levels)
    }

    private func height(at index: Int) -> CGFloat {
        guard index < levels.count else { return 4 }
        return max(4, CGFloat(levels[index]) * maxHeight)
    }
}
