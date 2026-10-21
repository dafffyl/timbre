//
//  MeetingStatsView.swift
//  Timbre
//

import Charts
import SwiftUI
import TimbreDiarization

/// Texte localisé du catalogue `Stats.xcstrings` (ADR-0008) ; `args` remplit
/// les `%@`/`%lld` de la valeur traduite.
func statsText(_ key: String, _ args: CVarArg...) -> String {
    let format = NSLocalizedString(key, tableName: "Stats", bundle: .main, value: key, comment: "")
    return args.isEmpty ? format : String(format: format, locale: .current, arguments: args)
}

/// Durée lisible et localisée : « 1 h 12 min », « 42 min 10 s ».
func statsDuration(_ seconds: TimeInterval) -> String {
    Duration.seconds(seconds.rounded()).formatted(
        .units(allowed: [.hours, .minutes, .seconds], width: .abbreviated, maximumUnitCount: 2))
}

/// Horloge compacte pour les axes : « 4:05 » ou « 1:04:05 ».
func statsClock(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded())
    let (h, m, s) = (total / 3600, total % 3600 / 60, total % 60)
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

/// Écran « Stats » d'une réunion : tout est dérivé de `MeetingStats`, rien
/// n'est calculé ici (ADR-0008). Les couleurs suivent l'ordre de première
/// apparition des locuteurs, comme le transcript.
struct MeetingStatsView: View {
    let stats: MeetingStats
    let labels: [SpeakerID: String]
    let order: [SpeakerID]
    let recordedAt: Date

    @State private var appeared = false
    @State private var shareImage: Image?

    private func color(_ speaker: SpeakerID?) -> Color {
        TranscriptFormatting.accentColor(forIndex: speaker.flatMap { order.firstIndex(of: $0) })
    }

    private func label(_ speaker: SpeakerID) -> String { labels[speaker] ?? speaker.rawValue }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                hero
                if !stats.hasTimings { legacyBanner }
                if let score = stats.balanceScore { balanceCard(score) }
                if stats.hasTimings { conversationCard }
                if stats.rhythm.count >= 3 { rhythmCard }
                if stats.hasTimings { recordsCard }
                if !stats.keywords.isEmpty { keywordsCard }
                participantsSection
                shareButton
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .onAppear { withAnimation(.easeOut(duration: 1.1)) { appeared = true } }
        .sensoryFeedback(.success, trigger: appeared)
        .task { renderShareCard() }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 20) {
            HStack(spacing: 22) {
                if let ratio = stats.speechRatio {
                    speechRing(ratio)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(statsText("stats.hero.duration"))
                        .font(.timbreCaption())
                        .foregroundStyle(Color.timbreTextSecondary)
                    Text(stats.totalDuration.map(statsDuration) ?? "—")
                        .font(.timbreDisplay(34))
                        .foregroundStyle(LinearGradient.timbreAccent)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 0) {
                tile(value: stats.wordCount.formatted(), label: statsText("stats.hero.words"))
                if let wpm = stats.wordsPerMinute {
                    tile(value: Int(wpm.rounded()).formatted(), label: statsText("stats.hero.wpm"))
                }
                tile(value: stats.participants.count.formatted(), label: statsText("stats.hero.people"))
            }
        }
        .timbreCard()
        .accessibilityElement(children: .combine)
    }

    private func speechRing(_ ratio: Double) -> some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 12)
            Circle()
                .trim(from: 0, to: appeared ? ratio : 0)
                .stroke(LinearGradient.timbreAccent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(Int((ratio * 100).rounded()))%")
                    .font(.timbreTitle(24))
                    .foregroundStyle(Color.timbreTextPrimary)
                Text(statsText("stats.hero.speech"))
                    .font(.timbreCaption(11))
                    .foregroundStyle(Color.timbreTextSecondary)
            }
        }
        .frame(width: 112, height: 112)
    }

    private func tile(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.timbreTitle(22))
                .foregroundStyle(Color.timbreTextPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.timbreCaption(12))
                .foregroundStyle(Color.timbreTextSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var legacyBanner: some View {
        Label(statsText("stats.legacy"), systemImage: "clock.badge.exclamationmark")
            .font(.timbreCaption())
            .foregroundStyle(Color.timbreCoral)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.timbreCoral.opacity(0.14), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Équilibre

    private func balanceCard(_ score: Int) -> some View {
        let verdict: String =
            switch score {
            case 80...: statsText("stats.balance.verdict.great")
            case 55..<80: statsText("stats.balance.verdict.good")
            case 30..<55: statsText("stats.balance.verdict.skewed")
            default: statsText("stats.balance.verdict.solo")
            }
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                sectionTitle(statsText("stats.balance.title"))
                Spacer()
                Text("\(score)")
                    .font(.timbreDisplay(34))
                    .foregroundStyle(LinearGradient.timbreAccent)
                Text("/100")
                    .font(.timbreCaption())
                    .foregroundStyle(Color.timbreTextSecondary)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient.timbreAccent)
                        .frame(width: max(14, geometry.size.width * (appeared ? Double(score) / 100 : 0)))
                }
            }
            .frame(height: 14)
            Text(verdict)
                .font(.timbreLabel())
                .foregroundStyle(Color.timbreTextPrimary)
        }
        .timbreCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(statsText("stats.a11y.balance", score) + ". " + verdict)
    }

    // MARK: - Conversation

    private var conversationCard: some View {
        let total = max(stats.totalDuration ?? 1, 1)
        let maxExchanges = max(1, stats.rhythm.map(\.exchanges).max() ?? 1)
        return VStack(alignment: .leading, spacing: 12) {
            sectionTitle(statsText("stats.convo.title"))

            Canvas { context, size in
                for segment in stats.timeline {
                    let x = segment.start / total * size.width
                    let width = max(1.5, (segment.end - segment.start) / total * size.width)
                    let rect = CGRect(x: x, y: 0, width: width, height: size.height)
                    context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(color(segment.speaker)))
                }
            }
            .frame(height: 46)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(statsText("stats.a11y.timeline"))

            if stats.rhythm.contains(where: { $0.exchanges > 0 }) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 2) {
                        ForEach(Array(stats.rhythm.enumerated()), id: \.offset) { _, bucket in
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(Color.timbreCoral)
                                .opacity(0.12 + 0.88 * Double(bucket.exchanges) / Double(maxExchanges))
                                .frame(maxWidth: .infinity)
                                .frame(height: 10)
                                .layoutPriority(bucket.length)
                        }
                    }
                    .accessibilityHidden(true)
                    Text(statsText("stats.convo.hot"))
                        .font(.timbreCaption(11))
                        .foregroundStyle(Color.timbreTextSecondary)
                }
            }

            HStack {
                Text(statsClock(0))
                Spacer()
                Text(statsClock(total / 2))
                Spacer()
                Text(statsClock(total))
            }
            .font(.timbreCaption(11))
            .foregroundStyle(Color.timbreTextSecondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(stats.participants) { participant in
                    legend(color(participant.speaker), label(participant.speaker))
                }
                if stats.timeline.contains(where: { $0.speaker == nil }) {
                    legend(color(nil), statsText("stats.convo.unattributed"))
                }
            }
        }
        .timbreCard()
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text)
                .font(.timbreCaption(12))
                .foregroundStyle(Color.timbreTextPrimary)
                .lineLimit(1)
        }
    }

    // MARK: - Rythme

    private var rhythmCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                sectionTitle(statsText("stats.rhythm.title"))
                Text(statsText("stats.rhythm.subtitle"))
                    .font(.timbreCaption(12))
                    .foregroundStyle(Color.timbreTextSecondary)
            }
            Chart(stats.rhythm, id: \.start) { bucket in
                AreaMark(
                    x: .value("t", bucket.start + bucket.length / 2),
                    y: .value("wpm", appeared ? bucket.wordsPerMinute : 0)
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.timbreViolet.opacity(0.55), Color.timbreViolet.opacity(0)],
                        startPoint: .top, endPoint: .bottom))
                LineMark(
                    x: .value("t", bucket.start + bucket.length / 2),
                    y: .value("wpm", appeared ? bucket.wordsPerMinute : 0)
                )
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                .foregroundStyle(LinearGradient.timbreAccent)
            }
            .chartXAxis { timeAxis }
            .chartYAxis { valueAxis }
            .frame(height: 140)

            VStack(alignment: .leading, spacing: 2) {
                sectionTitle(statsText("stats.intensity.title"))
                Text(statsText("stats.intensity.subtitle"))
                    .font(.timbreCaption(12))
                    .foregroundStyle(Color.timbreTextSecondary)
            }
            Chart(stats.rhythm, id: \.start) { bucket in
                BarMark(
                    xStart: .value("start", bucket.start + bucket.length * 0.12),
                    xEnd: .value("end", bucket.start + bucket.length * 0.88),
                    y: .value("n", appeared ? bucket.exchanges : 0)
                )
                .cornerRadius(4)
                .foregroundStyle(Color.timbreCoral.gradient)
            }
            .chartXAxis { timeAxis }
            .chartYAxis { valueAxis }
            .frame(height: 110)
        }
        .timbreCard()
        .accessibilityElement(children: .contain)
    }

    private var timeAxis: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 4)) { value in
            AxisValueLabel {
                if let seconds = value.as(Double.self) { Text(statsClock(seconds)) }
            }
            .foregroundStyle(Color.timbreTextSecondary)
        }
    }

    private var valueAxis: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 3)) { _ in
            AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
            AxisValueLabel().foregroundStyle(Color.timbreTextSecondary)
        }
    }

    // MARK: - Records

    private var recordsCard: some View {
        let peak = stats.rhythm.max { $0.exchanges < $1.exchanges }.flatMap { $0.exchanges > 0 ? $0 : nil }
        return VStack(alignment: .leading, spacing: 14) {
            sectionTitle(statsText("stats.records.title"))
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 12) {
                record(
                    icon: "scissors", value: stats.interruptionCount.formatted(),
                    label: statsText("stats.records.interruptions"),
                    note: statsText("stats.records.interruptions.note"))
                if let monologue = stats.longestMonologue {
                    record(
                        icon: "mic.fill", value: statsDuration(monologue.duration),
                        label: statsText("stats.records.monologue"),
                        note: statsText("stats.records.by", label(monologue.speaker)))
                }
                if let peak {
                    record(
                        icon: "flame.fill", value: statsClock(peak.start + peak.length / 2),
                        label: statsText("stats.records.peak"),
                        note: "\(peak.exchanges) ↔")
                }
            }
        }
        .timbreCard()
    }

    private func record(icon: String, value: String, label: String, note: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(LinearGradient.timbreAccent)
            Text(value)
                .font(.timbreTitle(22))
                .foregroundStyle(Color.timbreTextPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
            Text(label)
                .font(.timbreCaption(12))
                .foregroundStyle(Color.timbreTextPrimary)
            Text(note)
                .font(.timbreCaption(11))
                .foregroundStyle(Color.timbreTextSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: - Mots-clés

    private var keywordsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(statsText("stats.keywords.title"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(stats.keywords, id: \.word) { keyword in
                    HStack(spacing: 6) {
                        Text(keyword.word)
                            .font(.timbreLabel(14))
                            .foregroundStyle(Color.timbreTextPrimary)
                            .lineLimit(1)
                        Text("×\(keyword.count)")
                            .font(.timbreCaption(11))
                            .foregroundStyle(Color.timbreCoral)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(Color.timbreViolet.opacity(0.16), in: Capsule())
                }
            }
        }
        .timbreCard()
    }

    // MARK: - Participants

    private var participantsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(statsText("stats.people.title"))
                .padding(.horizontal, 4)
            ForEach(Array(stats.participants.enumerated()), id: \.element.id) { rank, participant in
                participantCard(participant, rank: rank + 1)
            }
        }
    }

    private func participantCard(_ participant: ParticipantStats, rank: Int) -> some View {
        let accent = color(participant.speaker)
        let name = label(participant.speaker)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(accent.opacity(0.2)).frame(width: 40, height: 40)
                    Text("\(rank)")
                        .font(.timbreTitle(18))
                        .foregroundStyle(accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.timbreTitle(18))
                        .foregroundStyle(Color.timbreTextPrimary)
                        .lineLimit(1)
                    if let title = participant.title {
                        titleBadge(title, participant: participant, accent: accent)
                    }
                }
                Spacer(minLength: 8)
                Text("\(Int((participant.share * 100).rounded()))%")
                    .font(.timbreDisplay(30))
                    .foregroundStyle(accent)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.08))
                    Capsule()
                        .fill(accent.gradient)
                        .frame(width: max(10, geometry.size.width * (appeared ? participant.share : 0)))
                }
            }
            .frame(height: 10)

            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 12) {
                ForEach(metrics(for: participant), id: \.label) { metric in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(metric.value)
                            .font(.timbreLabel(16))
                            .foregroundStyle(Color.timbreTextPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(metric.label)
                            .font(.timbreCaption(11))
                            .foregroundStyle(Color.timbreTextSecondary)
                    }
                }
            }

            if let thirds = participant.shareByThird {
                thirdsView(thirds, accent: accent)
            }
        }
        .timbreCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(statsText("stats.a11y.share", name, Int((participant.share * 100).rounded())))
    }

    private struct Metric {
        let label: String
        let value: String
    }

    private func metrics(for p: ParticipantStats) -> [Metric] {
        var result: [Metric] = []
        if let time = p.speakingTime {
            result.append(Metric(label: statsText("stats.person.time"), value: statsDuration(time)))
        }
        result.append(Metric(label: statsText("stats.person.words"), value: p.wordCount.formatted()))
        if let wpm = p.wordsPerMinute {
            result.append(Metric(label: statsText("stats.person.wpm"), value: Int(wpm.rounded()).formatted()))
        }
        result.append(Metric(label: statsText("stats.person.turns"), value: p.turnCount.formatted()))
        result.append(
            Metric(
                label: statsText("stats.person.wordsPerTurn"),
                value: p.averageWordsPerTurn.formatted(.number.precision(.fractionLength(0)))))
        if let delay = p.averageReactionDelay {
            result.append(Metric(label: statsText("stats.person.reaction"), value: secondsText(delay)))
        }
        if stats.hasTimings {
            result.append(
                Metric(
                    label: statsText("stats.person.interrupts"),
                    value: statsText("stats.person.interrupts.value", p.interruptionsMade, p.interruptionsReceived)))
        }
        return result
    }

    private func secondsText(_ seconds: TimeInterval) -> String {
        seconds.formatted(.number.precision(.fractionLength(1))) + " s"
    }

    private func titleBadge(_ title: ParticipantTitle, participant: ParticipantStats, accent: Color) -> some View {
        let (icon, name, detail): (String, String, String) =
            switch title {
            case .chatterbox:
                ("text.bubble.fill", statsText("stats.title.chatterbox"),
                 statsText("stats.title.chatterbox.detail", participant.wordCount))
            case .interrupter:
                ("scissors", statsText("stats.title.interrupter"),
                 statsText("stats.title.interrupter.detail", participant.interruptionsMade))
            case .lightning:
                ("bolt.fill", statsText("stats.title.lightning"),
                 statsText("stats.title.lightning.detail", secondsText(participant.averageReactionDelay ?? 0)))
            case .strategist:
                ("brain.head.profile", statsText("stats.title.strategist"), statsText("stats.title.strategist.detail"))
            }
        return VStack(alignment: .leading, spacing: 1) {
            Label(name, systemImage: icon)
                .font(.timbreCaption(12))
                .foregroundStyle(accent)
            Text(detail)
                .font(.timbreCaption(11))
                .foregroundStyle(Color.timbreTextSecondary)
        }
    }

    private func thirdsView(_ thirds: [Double], accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(statsText("stats.person.thirds"))
                .font(.timbreCaption(11))
                .foregroundStyle(Color.timbreTextSecondary)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(thirds.enumerated()), id: \.offset) { index, share in
                    VStack(spacing: 4) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(accent.gradient)
                                .frame(height: max(3, 44 * (appeared ? share : 0)))
                        }
                        .frame(height: 44)
                        Text(statsText("stats.person.third\(index + 1)"))
                            .font(.timbreCaption(10))
                            .foregroundStyle(Color.timbreTextSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Partage

    @ViewBuilder
    private var shareButton: some View {
        if let shareImage {
            ShareLink(
                item: shareImage,
                preview: SharePreview(statsText("stats.share.preview"), image: shareImage)
            ) {
                Label(statsText("stats.share.button"), systemImage: "square.and.arrow.up")
            }
            .buttonStyle(TimbrePrimaryButtonStyle())
        }
    }

    /// Rend la carte de partage en image une fois pour toutes à l'ouverture :
    /// `ShareLink` a besoin de l'élément avant le tap.
    private func renderShareCard() {
        let card = MeetingStatsShareCard(stats: stats, labels: labels, order: order, recordedAt: recordedAt)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        if let image = renderer.uiImage { shareImage = Image(uiImage: image) }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.timbreTitle(18))
            .foregroundStyle(Color.timbreTextPrimary)
    }
}
