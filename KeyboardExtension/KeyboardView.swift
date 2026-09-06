import SwiftUI
import TimbreCore

/// Thème sombre forcé, indépendant de l'apparence système — c'est le look
/// visé (cf. capture de référence), pas encore adaptatif clair/sombre.
struct KeyboardView: View {
    let layout: KeyboardLayout
    var viewModel: DictationViewModel
    let onKeyTap: (String) -> Void
    let onDeleteTap: () -> Void
    let onMicTap: () -> Void
    let onStopRecordingTap: () -> Void
    let onCancelTap: () -> Void
    let onDismissError: () -> Void
    let onHapticTap: () -> Void

    /// Effet ponctuel : une majuscule puis retour en minuscule, comme le
    /// clavier système — pas de verrouillage majuscules dans cette version.
    @State private var isShifted = false

    /// Historique glissant des derniers niveaux reçus — on n'a qu'un
    /// scalaire d'amplitude par tick (pas de vrai spectre de fréquences),
    /// donc l'effet "onde" vient de faire défiler cet historique en barres,
    /// pas d'une vraie analyse fréquentielle.
    @State private var levelHistory: [Float] = []
    private let waveformBarCount = 20

    private let keyBackground = Color(white: 0.30)
    private let cardBackground = Color(white: 0.15)

    var body: some View {
        VStack(spacing: 8) {
            topBar
                // Espace réservé au vrai UIButton "clavier suivant" (UIKit,
                // superposé par-dessus) — voir KeyboardViewController.
                .padding(.leading, 44)

            ForEach(Array(layout.rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 5) {
                    if index == 2 {
                        modifierKey(systemImage: isShifted ? "shift.fill" : "shift") {
                            isShifted.toggle()
                        }
                    }

                    ForEach(row, id: \.self) { key in
                        letterKey(key)
                    }

                    if index == 2 {
                        modifierKey(systemImage: "delete.left", action: onDeleteTap)
                    }
                }
            }

            bottomRow
        }
        .padding(8)
        .background(cardBackground)
        .preferredColorScheme(.dark)
        .onChange(of: viewModel.state) { _, newState in
            if newState != .recording {
                levelHistory.removeAll()
            }
        }
    }

    private var topBar: some View {
        HStack {
            Spacer()
            micButton
        }
    }

    @ViewBuilder
    private var micButton: some View {
        switch viewModel.state {
        case .idle:
            Button(action: onMicTap) {
                HStack(spacing: 6) {
                    Text("Start")
                    Image(systemName: "waveform")
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

        case .fullAccessRequired:
            Text("Autorise l'accès complet dans Réglages")
                .font(.caption2)
                .foregroundStyle(.orange)

        case .opening:
            progressPill(label: "Ouverture de Timbre…") {
                Button("Annuler", action: onCancelTap)
                    .font(.caption)
            }

        case .recording:
            HStack(spacing: 10) {
                waveform

                Button(action: onCancelTap) {
                    Image(systemName: "xmark.circle.fill")
                }
                Button(action: onStopRecordingTap) {
                    Image(systemName: "checkmark.circle.fill")
                }
            }
            .font(.title3)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.15))
            .clipShape(Capsule())
            .onChange(of: viewModel.audioLevel) { _, newLevel in
                levelHistory.append(newLevel)
                if levelHistory.count > waveformBarCount {
                    levelHistory.removeFirst()
                }
            }

        case .transcribing:
            progressPill(label: "Transcription…") {
                EmptyView()
            }

        case .error(let message):
            Button(action: onDismissError) {
                HStack(spacing: 6) {
                    Text(message)
                        .font(.caption2)
                    Text("OK").bold()
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.red.opacity(0.6))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    private var waveform: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(levelHistory.enumerated()), id: \.offset) { _, level in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white)
                    .frame(width: 3, height: barHeight(for: level))
            }
        }
        .frame(width: CGFloat(waveformBarCount) * 6, height: 24)
    }

    private func barHeight(for level: Float) -> CGFloat {
        4 + CGFloat(level) * 20
    }

    private func progressPill(label: String, @ViewBuilder trailing: () -> some View) -> some View {
        HStack(spacing: 8) {
            ProgressView().tint(.white)
            Text(label)
                .font(.caption)
                .foregroundStyle(.white)
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.15))
        .clipShape(Capsule())
    }

    private func letterKey(_ key: String) -> some View {
        Button {
            tapLetter(key)
        } label: {
            Text(isShifted ? key.uppercased() : key.lowercased())
                .font(.title3)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(keyBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func modifierKey(systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            onHapticTap()
            action()
        } label: {
            Image(systemName: systemImage)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(keyBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private var bottomRow: some View {
        HStack(spacing: 5) {
            Text("123")
                .foregroundStyle(.white)
                .frame(width: 60)
                .padding(.vertical, 12)
                .background(keyBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            Button {
                onHapticTap()
                onKeyTap(" ")
            } label: {
                Text("Timbre")
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(keyBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            modifierKey(systemImage: "arrow.turn.down.left") {
                onKeyTap("\n")
            }
            .frame(width: 60)
        }
    }

    private func tapLetter(_ key: String) {
        onHapticTap()
        onKeyTap(isShifted ? key.uppercased() : key.lowercased())
        isShifted = false
    }
}

#Preview {
    KeyboardView(
        layout: .azerty,
        viewModel: DictationViewModel(),
        onKeyTap: { _ in },
        onDeleteTap: {},
        onMicTap: {},
        onStopRecordingTap: {},
        onCancelTap: {},
        onDismissError: {},
        onHapticTap: {}
    )
}
