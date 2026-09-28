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

    /// `.off`/`.shifted` : effet ponctuel, une majuscule puis retour en
    /// minuscule, comme le clavier système. `.locked` : verrouillage
    /// majuscule (double-tap sur shift), ne se réinitialise pas après une
    /// lettre.
    private enum ShiftState: Equatable {
        case off, shifted, locked
    }
    @State private var shiftState: ShiftState = .off
    @State private var lastShiftTapAt: Date?

    /// Bascule "123" ↔ "ABC" — seule la page chiffres/ponctuation la plus
    /// fréquente (`KeyboardLayout.numbersAndPunctuation`), pas la page
    /// "#+=" secondaire du clavier système, laissée pour un incrément
    /// ultérieur.
    @State private var isNumericPage = false

    /// Lettre dont l'appui long affiche les variantes accentuées, `nil` si
    /// aucun picker n'est ouvert. Remis à `nil` dès qu'une touche lettre est
    /// tapée normalement (voir `tapLetter`), pour ne pas laisser un picker
    /// ouvert traîner visuellement après que l'utilisateur a changé d'avis.
    @State private var pendingAccentLetter: String?

    @State private var deleteRepeatTimer: Timer?

    /// Historique glissant des derniers niveaux reçus — on n'a qu'un
    /// scalaire d'amplitude par tick (pas de vrai spectre de fréquences),
    /// donc l'effet "onde" vient de faire défiler cet historique en barres,
    /// pas d'une vraie analyse fréquentielle.
    @State private var levelHistory: [Float] = []
    private let waveformBarCount = 20

    private let keyBackground = Color(white: 0.30)
    private let cardBackground = Color(white: 0.15)

    private var isUppercase: Bool { shiftState != .off }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 8) {
                topBar
                    // Espace réservé au vrai UIButton "clavier suivant" (UIKit,
                    // superposé par-dessus) — voir KeyboardViewController.
                    .padding(.leading, 44)

                ForEach(Array(currentRows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 5) {
                        if index == 2 && !isNumericPage {
                            shiftKey
                        }

                        ForEach(row, id: \.self) { key in
                            if isNumericPage {
                                symbolKey(key)
                            } else {
                                letterKey(key)
                            }
                        }

                        if index == 2 {
                            deleteKey
                        }
                    }
                }

                bottomRow
            }
            .padding(8)
            .background(cardBackground)

            if let letter = pendingAccentLetter {
                accentPicker(for: letter)
                    .padding(.top, 44)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: viewModel.state) { _, newState in
            if newState != .recording {
                levelHistory.removeAll()
            }
        }
    }

    private var currentRows: [[String]] {
        isNumericPage ? KeyboardLayout.numbersAndPunctuation.rows : layout.rows
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
            Text(isUppercase ? key.uppercased() : key.lowercased())
                .font(.title3)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(keyBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        // `.simultaneousGesture` plutôt que `.onLongPressGesture` : coexiste
        // avec le tap du `Button` sans l'annuler — un appui long doit quand
        // même pouvoir se terminer en tap simple normal (relâché avant le
        // seuil), ce que `.onLongPressGesture` seul gère moins fiablement
        // une fois combiné à un `Button`.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                guard !DiacriticVariants.variants(for: key).isEmpty else { return }
                onHapticTap()
                pendingAccentLetter = key
            }
        )
    }

    /// Touche de la page "123" — chiffre ou ponctuation, jamais de casse ni
    /// de variante accentuée (contrairement à `letterKey`).
    private func symbolKey(_ key: String) -> some View {
        Button {
            onHapticTap()
            onKeyTap(key)
        } label: {
            Text(key)
                .font(.title3)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(keyBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    /// Barre de variantes accentuées affichée en overlay pendant l'appui
    /// long — position fixe sous la barre du haut plutôt que juste au-dessus
    /// de la touche exacte (contrairement au clavier système) : suffisant
    /// pour être fonctionnel, le positionnement précis relève de la passe
    /// UI prévue plus tard. La lettre de base est incluse en premier, comme
    /// au clavier système (relâcher sans glisser insère la lettre simple).
    private func accentPicker(for letter: String) -> some View {
        let variants = [letter] + DiacriticVariants.variants(for: letter)
        return HStack(spacing: 6) {
            ForEach(variants, id: \.self) { variant in
                Button {
                    onHapticTap()
                    onKeyTap(isUppercase ? variant.uppercased() : variant.lowercased())
                    if shiftState == .shifted {
                        shiftState = .off
                    }
                    pendingAccentLetter = nil
                } label: {
                    Text(isUppercase ? variant.uppercased() : variant.lowercased())
                        .font(.title3)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color(white: 0.35))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var shiftKey: some View {
        Button {
            tapShift()
        } label: {
            Image(systemName: shiftState == .locked ? "capslock.fill" : (shiftState == .shifted ? "shift.fill" : "shift"))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(keyBackground)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    /// Distincte de `modifierKey` : les autres touches modificatrices
    /// n'ont besoin que d'un tap simple, celle-ci doit répéter tant qu'elle
    /// reste enfoncée, comme au clavier système — un `Button` seul ne le
    /// permet pas, d'où le geste manuel.
    private var deleteKey: some View {
        Image(systemName: "delete.left")
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(keyBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in startDeleteRepeatIfNeeded() }
                    .onEnded { _ in stopDeleteRepeat() }
            )
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
            Button {
                onHapticTap()
                isNumericPage.toggle()
            } label: {
                Text(isNumericPage ? "ABC" : "123")
                    .foregroundStyle(.white)
                    .frame(width: 60)
                    .padding(.vertical, 12)
                    .background(keyBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

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
        onKeyTap(isUppercase ? key.uppercased() : key.lowercased())
        pendingAccentLetter = nil
        if shiftState == .shifted {
            shiftState = .off
        }
    }

    /// Tap simple : bascule off ↔ shifted (effet ponctuel), comme avant.
    /// Double-tap rapide (< 0,3s) : verrouille (`.locked`), comme le clavier
    /// système — se déverrouille ensuite par un tap simple.
    private func tapShift() {
        onHapticTap()
        let now = Date()
        let isDoubleTap = lastShiftTapAt.map { now.timeIntervalSince($0) < 0.3 } ?? false
        lastShiftTapAt = now

        if isDoubleTap {
            shiftState = .locked
            return
        }

        switch shiftState {
        case .off:
            shiftState = .shifted
        case .shifted, .locked:
            shiftState = .off
        }
    }

    /// Délai initial avant répétition (comme le clavier système, pour ne pas
    /// supprimer deux caractères sur un tap un peu long), puis répétition à
    /// rythme fixe — pas d'accélération progressive comme au clavier système,
    /// laissé pour la passe UI ultérieure.
    private func startDeleteRepeatIfNeeded() {
        guard deleteRepeatTimer == nil else { return }
        onHapticTap()
        onDeleteTap()
        deleteRepeatTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { _ in
            deleteRepeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                onDeleteTap()
            }
        }
    }

    private func stopDeleteRepeat() {
        deleteRepeatTimer?.invalidate()
        deleteRepeatTimer = nil
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
