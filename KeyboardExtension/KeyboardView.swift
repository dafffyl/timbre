import SwiftUI
import TimbreCore

/// Rendu purement visuel du clavier — Phase 1 valide la plomberie
/// (build, dépendances, CI), pas la fonctionnalité. Aucune touche n'insère
/// de texte, le bouton micro n'a aucune action : ça arrive en Phase 4.
struct KeyboardView: View {
    let layout: KeyboardLayout

    var body: some View {
        VStack(spacing: 6) {
            micPlaceholder

            ForEach(Array(layout.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { key in
                        Text(key)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color(.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .padding(6)
    }

    private var micPlaceholder: some View {
        Image(systemName: "mic.fill")
            .font(.title2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    KeyboardView(layout: .azerty)
}
