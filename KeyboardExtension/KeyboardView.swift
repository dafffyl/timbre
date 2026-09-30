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
    /// aucun picker n'est ouvert.
    @State private var pendingAccentLetter: String?
    @State private var accentLongPressTimer: Timer?

    /// Variante actuellement survolée par le doigt pendant le glissé —
    /// permet de surligner l'option sous le doigt, comme au clavier système.
    @State private var hoveredVariant: String?

    /// Cadre de chaque bouton de variante, dans l'espace de coordonnées
    /// nommé "keyboard" (posé sur le `ZStack` racine) — nécessaire pour
    /// traduire la position du doigt (rapportée par un seul geste continu
    /// depuis la lettre jusqu'au picker) en "quelle variante est en dessous".
    /// Des `Button` indépendants pour chaque variante ne suffisent pas : un
    /// glissé continu depuis la touche lettre ne déclenche jamais le tap
    /// d'un autre `Button` qu'on relâche au-dessus sans y avoir appuyé.
    @State private var accentVariantFrames: [String: CGRect] = [:]

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
        // Nommé pour que `letterGesture` puisse convertir la position du
        // doigt en coordonnées comparables aux cadres capturés par
        // `accentPicker`, quel que soit l'ancêtre commun réel dans l'arbre
        // de vues.
        .coordinateSpace(name: "keyboard")
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

    /// Pas de `Button` ici, volontairement : un tap simple et un appui long
    /// suivi d'un glissé jusqu'au picker de variantes sont un seul et même
    /// geste continu (le doigt ne quitte jamais l'écran entre les deux). Un
    /// `Button` par variante ne peut pas recevoir un relâché qui a commencé
    /// ailleurs — d'où un unique `DragGesture` qui suit le doigt du début à
    /// la fin et décide, à la fin seulement, ce qu'il faut insérer.
    private func letterKey(_ key: String) -> some View {
        Text(isUppercase ? key.uppercased() : key.lowercased())
            .font(.title3)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(pendingAccentLetter == key ? Color.white.opacity(0.25) : keyBackground)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
            .gesture(letterGesture(for: key))
    }

    private func letterGesture(for key: String) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("keyboard"))
            .onChanged { value in
                if pendingAccentLetter == nil && accentLongPressTimer == nil {
                    startAccentTimer(for: key)
                }
                if pendingAccentLetter != nil {
                    hoveredVariant = variant(at: value.location, for: key)
                }
            }
            .onEnded { value in
                accentLongPressTimer?.invalidate()
                accentLongPressTimer = nil

                if pendingAccentLetter != nil {
                    let selected = variant(at: value.location, for: key)
                    pendingAccentLetter = nil
                    hoveredVariant = nil
                    insertLetterOrVariant(base: key, selected: selected)
                } else {
                    tapLetter(key)
                }
            }
    }

    /// Démarre le délai avant affichage du picker — un vrai `Timer`, pas un
    /// simple minimum sur `LongPressGesture`, pour continuer à courir même
    /// si le doigt reste parfaitement immobile (`onChanged` ne se
    /// redéclenche pas sans mouvement, `Timer` si). Rien ne se passe pour
    /// une lettre sans variante : le relâchement retombe alors sur
    /// `tapLetter` normalement.
    private func startAccentTimer(for key: String) {
        guard !DiacriticVariants.variants(for: key).isEmpty else { return }
        accentLongPressTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { _ in
            onHapticTap()
            pendingAccentLetter = key
        }
    }

    /// Ne cherche que parmi les variantes de `letter` (la lettre dont le
    /// picker est ouvert), jamais tout `accentVariantFrames` — sans ce
    /// filtre, un cadre laissé par un picker précédent sur une autre lettre
    /// pourrait matcher par coïncidence de position à l'écran.
    private func variant(at point: CGPoint, for letter: String) -> String? {
        let candidates = [letter] + DiacriticVariants.variants(for: letter)
        return candidates.first { candidate in
            accentVariantFrames[candidate]?.contains(point) ?? false
        }
    }

    /// `selected == nil` : le doigt a été relâché hors de toute variante
    /// reconnue (dont la lettre de base elle-même) — on insère quand même la
    /// lettre de base plutôt que de ne rien faire, un peu plus permissif que
    /// le clavier système (qui annule si on glisse franchement hors du
    /// picker), pour éviter la frustration d'un tap qui ne produit rien.
    private func insertLetterOrVariant(base: String, selected: String?) {
        onHapticTap()
        let text = selected ?? base
        onKeyTap(isUppercase ? text.uppercased() : text.lowercased())
        if shiftState == .shifted {
            shiftState = .off
        }
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
    ///
    /// Pas de `Button` : la sélection se décide entièrement dans
    /// `letterGesture`, à partir des cadres capturés ici via
    /// `GeometryReader`. Cette vue ne fait qu'afficher, surligner celle
    /// survolée (`hoveredVariant`), et publier sa géométrie.
    private func accentPicker(for letter: String) -> some View {
        let variants = [letter] + DiacriticVariants.variants(for: letter)
        return HStack(spacing: 6) {
            ForEach(variants, id: \.self) { variant in
                Text(isUppercase ? variant.uppercased() : variant.lowercased())
                    .font(.title3)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(hoveredVariant == variant ? Color.white.opacity(0.35) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .background(
                        GeometryReader { geometry in
                            Color.clear
                                .onAppear {
                                    accentVariantFrames[variant] = geometry.frame(in: .named("keyboard"))
                                }
                                .onChange(of: geometry.frame(in: .named("keyboard"))) { _, newFrame in
                                    accentVariantFrames[variant] = newFrame
                                }
                        }
                    )
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
