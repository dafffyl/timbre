//
//  Theme.swift
//  Timbre
//
//  Système de design de l'app — palette et typographie construites autour
//  de l'identité déjà posée par l'icône (deux ondes, violet et corail, sur
//  fond presque noir : les "deux voix" que le timbre distingue). Point
//  d'entrée unique pour ne jamais avoir deux nuances de violet qui divergent
//  entre écrans.
//

import SwiftUI

// `nonisolated` sur chaque propriété : l'isolation MainActor par défaut du
// module (voir CLAUDE.md) s'appliquerait sinon à ces constantes immuables,
// qui n'en ont pas besoin — mêmes valeurs partout, lisibles depuis n'importe
// quel contexte (vues, modificateurs, initialiseurs statiques d'autres
// constantes comme `LinearGradient.timbreBackground` ci-dessous).
extension Color {
    nonisolated static let timbreBackgroundTop = Color(red: 0.051, green: 0.047, blue: 0.086)
    nonisolated static let timbreBackgroundBottom = Color(red: 0.102, green: 0.078, blue: 0.173)
    nonisolated static let timbreSurface = Color(red: 0.114, green: 0.106, blue: 0.169)

    nonisolated static let timbreViolet = Color(red: 0.588, green: 0.518, blue: 1.0)
    nonisolated static let timbreCoral = Color(red: 1.0, green: 0.588, blue: 0.361)

    nonisolated static let timbreTextPrimary = Color(red: 0.961, green: 0.953, blue: 0.980)
    nonisolated static let timbreTextSecondary = Color(red: 0.608, green: 0.588, blue: 0.690)

    nonisolated static let timbreDanger = Color(red: 1.0, green: 0.420, blue: 0.420)
}

extension LinearGradient {
    nonisolated static let timbreBackground = LinearGradient(
        colors: [.timbreBackgroundTop, .timbreBackgroundBottom],
        startPoint: .top,
        endPoint: .bottom
    )

    nonisolated static let timbreAccent = LinearGradient(
        colors: [.timbreViolet, .timbreCoral],
        startPoint: .leading,
        endPoint: .trailing
    )
}

/// `.rounded` partout — fait écho aux formes organiques des ondes de
/// l'icône, plus chaleureux que le système par défaut pour une app qui
/// parle de voix humaines.
extension Font {
    /// Le titre d'accueil reste à taille fixe : déjà très grand, le laisser
    /// croître casserait l'en-tête. Tout le reste suit Dynamic Type.
    static func timbreDisplay(_ size: CGFloat = 40) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }

    static func timbreTitle(_ size: CGFloat = 22) -> Font {
        scaled(size, weight: .semibold)
    }

    static func timbreBody(_ size: CGFloat = 17) -> Font {
        scaled(size, weight: .regular)
    }

    static func timbreLabel(_ size: CGFloat = 15) -> Font {
        scaled(size, weight: .medium)
    }

    static func timbreCaption(_ size: CGFloat = 13) -> Font {
        scaled(size, weight: .medium)
    }

    /// Ancre chaque taille de référence sur le style de texte système le
    /// plus proche (tailles par défaut : caption 12, footnote 13,
    /// subheadline 15, callout 16, body 17, title3 20, title2 22), pour que
    /// la police grandisse avec le réglage de taille de texte de l'utilisateur.
    private static func scaled(_ size: CGFloat, weight: Font.Weight) -> Font {
        let style: Font.TextStyle
        switch size {
        case ..<12.5: style = .caption
        case ..<14: style = .footnote
        case ..<15.5: style = .subheadline
        case ..<16.5: style = .callout
        case ..<18.5: style = .body
        case ..<21: style = .title3
        default: style = .title2
        }
        return .system(style, design: .rounded, weight: weight)
    }
}
