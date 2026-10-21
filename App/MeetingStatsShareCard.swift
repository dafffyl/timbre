//
//  MeetingStatsShareCard.swift
//  Timbre
//

import SwiftUI
import TimbreDiarization

/// Carte de partage (image) : le résumé d'une réunion en un coup d'œil.
/// Rendue par `ImageRenderer`, donc sans matériaux translucides ni vues
/// interactives — fonds unis et formes simples uniquement.
struct MeetingStatsShareCard: View {
    let stats: MeetingStats
    let labels: [SpeakerID: String]
    let order: [SpeakerID]
    let recordedAt: Date

    private func color(_ speaker: SpeakerID) -> Color {
        TranscriptFormatting.accentColor(forIndex: order.firstIndex(of: speaker))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Timbre")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.timbreViolet)
                Text(recordedAt.formatted(date: .long, time: .shortened))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.timbreTextSecondary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 18) {
                if let duration = stats.totalDuration {
                    figure(statsDuration(duration), statsText("stats.hero.duration"))
                }
                if let score = stats.balanceScore {
                    figure("\(score)/100", statsText("stats.balance.title"))
                }
            }

            VStack(spacing: 14) {
                ForEach(stats.participants.prefix(4)) { participant in
                    row(participant)
                }
            }

            Spacer(minLength: 0)

            Text(statsText("stats.share.footer"))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color.timbreTextSecondary)
        }
        .padding(26)
        .frame(width: 360, height: 460, alignment: .topLeading)
        .background(LinearGradient.timbreBackground)
        .environment(\.colorScheme, .dark)
    }

    private func figure(_ value: String, _ caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(LinearGradient.timbreAccent)
            Text(caption)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color.timbreTextSecondary)
        }
    }

    private func row(_ participant: ParticipantStats) -> some View {
        let accent = color(participant.speaker)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(labels[participant.speaker] ?? participant.speaker.rawValue)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.timbreTextPrimary)
                Spacer()
                Text("\(Int((participant.share * 100).rounded()))%")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(accent).frame(width: max(8, geometry.size.width * participant.share))
                }
            }
            .frame(height: 8)
            if let title = participant.title {
                Text(shortTitle(title))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(accent)
            }
        }
    }

    private func shortTitle(_ title: ParticipantTitle) -> String {
        switch title {
        case .chatterbox: statsText("stats.title.chatterbox")
        case .interrupter: statsText("stats.title.interrupter")
        case .lightning: statsText("stats.title.lightning")
        case .strategist: statsText("stats.title.strategist")
        }
    }
}
