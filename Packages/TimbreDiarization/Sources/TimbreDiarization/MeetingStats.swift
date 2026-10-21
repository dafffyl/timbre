import Foundation

/// Titre ludique décerné à un participant — voir ADR-0008. Le package ne
/// renvoie que le cas ; le libellé (fr/en) est un problème d'affichage.
public enum ParticipantTitle: Sendable, Equatable, CaseIterable {
    /// Le plus de mots.
    case chatterbox
    /// Coupe le plus souvent la parole.
    case interrupter
    /// Répond le plus vite.
    case lightning
    /// Peu de tours, mais les plus longs.
    case strategist
}

public struct ParticipantStats: Sendable, Equatable, Identifiable {
    public let speaker: SpeakerID
    public var id: SpeakerID { speaker }

    /// `nil` sans horodatage (réunion enregistrée avant `start`/`end`).
    public let speakingTime: TimeInterval?
    /// Part de la parole de la réunion, 0...1 : au temps de parole si les
    /// tours sont horodatés, sinon au nombre de mots.
    public let share: Double
    public let wordCount: Int
    public let wordsPerMinute: Double?
    public let turnCount: Int
    public let averageWordsPerTurn: Double
    public let averageTurnDuration: TimeInterval?
    /// Fois où ce participant a pris la parole sans silence (≤ 0,3 s) après
    /// quelqu'un d'autre — heuristique, voir ADR-0008.
    public let interruptionsMade: Int
    public let interruptionsReceived: Int
    /// Silence moyen avant ses prises de parole qui suivent un autre
    /// locuteur (hors pauses de plus de 5 s, qui ne sont pas des réactions).
    public let averageReactionDelay: TimeInterval?
    /// Nombre de prises de parole mesurées pour `averageReactionDelay`.
    public let reactionCount: Int
    /// Sa part de la parole dans chaque tiers de la réunion (début, milieu,
    /// fin). `nil` sans horodatage.
    public let shareByThird: [Double]?
    public internal(set) var title: ParticipantTitle?
}

/// Un bloc de la frise : qui parle, quand (secondes depuis le début).
public struct TimelineSegment: Sendable, Equatable {
    public let speaker: SpeakerID?
    public let start: TimeInterval
    public let end: TimeInterval
}

/// Une tranche de la réunion pour les courbes de rythme et d'intensité.
public struct RhythmBucket: Sendable, Equatable {
    public let start: TimeInterval
    public let length: TimeInterval
    public let wordsPerMinute: Double
    /// Changements de locuteur dans la tranche — l'« intensité » de
    /// l'échange.
    public let exchanges: Int
}

public struct Monologue: Sendable, Equatable {
    public let speaker: SpeakerID
    public let start: TimeInterval
    public let duration: TimeInterval
}

public struct Keyword: Sendable, Equatable {
    public let word: String
    public let count: Int
}

/// Statistiques dérivées d'un transcript — jamais persistées (ADR-0008).
public struct MeetingStats: Sendable, Equatable {
    /// `false` pour les réunions sans `start`/`end` : tout ce qui dépend du
    /// temps est alors absent (`nil`/vide), jamais approximé.
    public let hasTimings: Bool
    public let totalDuration: TimeInterval?
    public let speakingTime: TimeInterval?
    /// Part de la durée où quelqu'un parle, 0...1.
    public let speechRatio: Double?
    public let wordCount: Int
    public let wordsPerMinute: Double?
    /// Triés par part de parole décroissante.
    public let participants: [ParticipantStats]
    /// 0 (une seule personne parle) à 100 (parole parfaitement équilibrée).
    /// `nil` avec moins de deux participants.
    public let balanceScore: Int?
    public let longestMonologue: Monologue?
    public let interruptionCount: Int
    public let timeline: [TimelineSegment]
    public let rhythm: [RhythmBucket]
    public let keywords: [Keyword]
}

extension MeetingStats {
    /// Silence maximal entre deux tours de locuteurs différents pour parler
    /// de coupure de parole.
    static let interruptionGap: TimeInterval = 0.3
    /// Au-delà, le silence avant une prise de parole n'est plus une
    /// réaction mais une pause.
    static let reactionCutoff: TimeInterval = 5
    static let minimumReactionsForTitle = 3
    static let minimumInterruptionsForTitle = 2
    static let maxKeywords = 5
    /// Marqueur inséré par le pipeline quand un morceau n'a pas pu être
    /// transcrit (ADR-0005) : ce n'est pas de la parole.
    static let missingTranscriptionMarker = "[transcription indisponible]"

    /// `nil` si le transcript ne contient aucun mot.
    public static func compute(turns rawTurns: [SpeakerTurn]) -> MeetingStats? {
        let hasTimings = !rawTurns.isEmpty && rawTurns.allSatisfy { $0.start != nil && $0.end != nil }
        let turns = hasTimings ? rawTurns.sorted { ($0.start ?? 0) < ($1.start ?? 0) } : rawTurns
        let wordCounts = turns.map { words(in: $0.text).count }
        let totalWords = wordCounts.reduce(0, +)
        guard totalWords > 0 else { return nil }

        let timed: [TimedTurn] = hasTimings
            ? zip(turns, wordCounts).map {
                TimedTurn(
                    speaker: $0.speaker, start: $0.start ?? 0, end: max($0.start ?? 0, $0.end ?? 0), words: $1)
            } : []

        let totalDuration = timed.map(\.end).max()
        let speakingTime = hasTimings ? timed.reduce(0) { $0 + ($1.end - $1.start) } : nil
        let events = hasTimings ? transitions(in: timed) : []

        var participants = participantStats(
            turns: turns, wordCounts: wordCounts, totalWords: totalWords,
            timed: timed, events: events, totalDuration: totalDuration)
        participants = awardTitles(participants)

        return MeetingStats(
            hasTimings: hasTimings,
            totalDuration: totalDuration,
            speakingTime: speakingTime,
            speechRatio: speakingTime.flatMap { time in totalDuration.flatMap { $0 > 0 ? min(1, time / $0) : nil } },
            wordCount: totalWords,
            wordsPerMinute: speakingTime.flatMap { $0 > 0 ? Double(totalWords) / ($0 / 60) : nil },
            participants: participants,
            balanceScore: balanceScore(shares: participants.map(\.share)),
            longestMonologue: longestMonologue(in: timed),
            interruptionCount: events.filter(\.isInterruption).count,
            timeline: timed.map { TimelineSegment(speaker: $0.speaker, start: $0.start, end: $0.end) },
            rhythm: rhythm(timed: timed, events: events, totalDuration: totalDuration),
            keywords: keywords(in: turns)
        )
    }

    // MARK: - Tours horodatés

    private struct TimedTurn {
        let speaker: SpeakerID?
        let start: TimeInterval
        let end: TimeInterval
        let words: Int
    }

    /// Passage d'un tour à celui d'un autre locuteur (les deux identifiés).
    private struct Transition {
        let from: SpeakerID
        let to: SpeakerID
        let at: TimeInterval
        let gap: TimeInterval
        var isInterruption: Bool { gap <= MeetingStats.interruptionGap }
    }

    private static func transitions(in timed: [TimedTurn]) -> [Transition] {
        zip(timed, timed.dropFirst()).compactMap { previous, next in
            guard let from = previous.speaker, let to = next.speaker, from != to else { return nil }
            return Transition(from: from, to: to, at: next.start, gap: next.start - previous.end)
        }
    }

    // MARK: - Participants

    private static func participantStats(
        turns: [SpeakerTurn], wordCounts: [Int], totalWords: Int,
        timed: [TimedTurn], events: [Transition], totalDuration: TimeInterval?
    ) -> [ParticipantStats] {
        var order: [SpeakerID] = []
        for turn in turns {
            if let speaker = turn.speaker, !order.contains(speaker) { order.append(speaker) }
        }
        let hasTimings = !timed.isEmpty
        let attributedTime = timed.reduce(0.0) { $0 + ($1.speaker == nil ? 0 : $1.end - $1.start) }
        let attributedWords = zip(turns, wordCounts).reduce(0) { $0 + ($1.0.speaker == nil ? 0 : $1.1) }
        let thirds = totalDuration.map { [0, $0 / 3, $0 * 2 / 3, $0] }

        let stats = order.map { speaker -> ParticipantStats in
            let words = zip(turns, wordCounts).reduce(0) { $0 + ($1.0.speaker == speaker ? $1.1 : 0) }
            let own = timed.filter { $0.speaker == speaker }
            let turnCount = turns.filter { $0.speaker == speaker }.count
            let time = hasTimings ? own.reduce(0) { $0 + ($1.end - $1.start) } : nil
            let reactions = events.filter { $0.to == speaker && $0.gap <= reactionCutoff }.map { max(0, $0.gap) }

            let share: Double
            if let time, attributedTime > 0 {
                share = time / attributedTime
            } else {
                share = attributedWords > 0 ? Double(words) / Double(attributedWords) : 0
            }

            return ParticipantStats(
                speaker: speaker,
                speakingTime: time,
                share: share,
                wordCount: words,
                wordsPerMinute: time.flatMap { $0 > 0 ? Double(words) / ($0 / 60) : nil },
                turnCount: turnCount,
                averageWordsPerTurn: Double(words) / Double(max(1, turnCount)),
                averageTurnDuration: time.map { $0 / Double(max(1, turnCount)) },
                interruptionsMade: events.filter { $0.to == speaker && $0.isInterruption }.count,
                interruptionsReceived: events.filter { $0.from == speaker && $0.isInterruption }.count,
                averageReactionDelay: reactions.isEmpty ? nil : reactions.reduce(0, +) / Double(reactions.count),
                reactionCount: reactions.count,
                shareByThird: thirds.map { bounds in
                    (0..<3).map { index in
                        let total = timed.reduce(0.0) {
                            $0 + overlap($1.start, $1.end, bounds[index], bounds[index + 1])
                        }
                        let mine = own.reduce(0.0) {
                            $0 + overlap($1.start, $1.end, bounds[index], bounds[index + 1])
                        }
                        return total > 0 ? mine / total : 0
                    }
                },
                title: nil
            )
        }
        return stats.sorted {
            $0.share != $1.share ? $0.share > $1.share : $0.speaker.rawValue < $1.speaker.rawValue
        }
    }

    // MARK: - Titres ludiques

    /// Un titre par personne, une personne par titre, dans l'ordre de
    /// priorité des cas de `ParticipantTitle`. Rien avec moins de deux
    /// participants : un titre « comparatif » n'a de sens qu'à plusieurs.
    private static func awardTitles(_ participants: [ParticipantStats]) -> [ParticipantStats] {
        guard participants.count >= 2 else { return participants }
        var titles: [SpeakerID: ParticipantTitle] = [:]

        func award(_ title: ParticipantTitle, to candidates: [ParticipantStats], by better: (ParticipantStats, ParticipantStats) -> Bool) {
            let free = candidates.filter { titles[$0.speaker] == nil }
            let ranked = free.sorted {
                better($0, $1) || (!better($1, $0) && $0.speaker.rawValue < $1.speaker.rawValue)
            }
            if let winner = ranked.first { titles[winner.speaker] = title }
        }

        award(.chatterbox, to: participants) { $0.wordCount > $1.wordCount }
        award(.interrupter, to: participants.filter { $0.interruptionsMade >= minimumInterruptionsForTitle }) {
            $0.interruptionsMade > $1.interruptionsMade
        }
        award(
            .lightning,
            to: participants.filter { $0.reactionCount >= minimumReactionsForTitle }
        ) { ($0.averageReactionDelay ?? .infinity) < ($1.averageReactionDelay ?? .infinity) }
        award(.strategist, to: participants) { $0.averageWordsPerTurn > $1.averageWordsPerTurn }

        var result = participants
        for index in result.indices { result[index].title = titles[result[index].speaker] }
        return result
    }

    // MARK: - Équilibre, monologue

    /// Entropie de Shannon des parts, normalisée par ln(n) : 100 quand tout
    /// le monde parle autant, 0 quand une seule personne parle.
    static func balanceScore(shares: [Double]) -> Int? {
        let present = shares.filter { $0 > 0 }
        guard shares.count >= 2 else { return nil }
        guard present.count >= 2 else { return 0 }
        let entropy = -present.reduce(0) { $0 + $1 * log($1) }
        return Int((100 * entropy / log(Double(shares.count))).rounded())
    }

    private static func longestMonologue(in timed: [TimedTurn]) -> Monologue? {
        timed
            .filter { $0.speaker != nil }
            .max { ($0.end - $0.start) < ($1.end - $1.start) }
            .flatMap { turn in
                turn.speaker.map { Monologue(speaker: $0, start: turn.start, duration: turn.end - turn.start) }
            }
    }

    // MARK: - Rythme

    private static let bucketLengths: [TimeInterval] = [30, 60, 120, 300, 600, 900, 1800, 3600]

    private static func rhythm(
        timed: [TimedTurn], events: [Transition], totalDuration: TimeInterval?
    ) -> [RhythmBucket] {
        guard let totalDuration, totalDuration > 0 else { return [] }
        let length = bucketLengths.first { totalDuration / $0 <= 12 } ?? bucketLengths.last ?? 3600
        let count = Int((totalDuration / length).rounded(.up))
        return (0..<count).map { index in
            let start = Double(index) * length
            let end = min(start + length, totalDuration)
            let words = timed.reduce(0.0) { sum, turn in
                let span = turn.end - turn.start
                guard span > 0 else { return sum + (turn.start >= start && turn.start < end ? Double(turn.words) : 0) }
                return sum + Double(turn.words) * overlap(turn.start, turn.end, start, end) / span
            }
            let exchanges = events.filter { $0.at >= start && $0.at < end }.count
            return RhythmBucket(
                start: start, length: end - start,
                wordsPerMinute: words / ((end - start) / 60), exchanges: exchanges)
        }
    }

    private static func overlap(_ a0: TimeInterval, _ a1: TimeInterval, _ b0: TimeInterval, _ b1: TimeInterval) -> TimeInterval {
        max(0, min(a1, b1) - max(a0, b0))
    }

    // MARK: - Mots

    private static func words(in text: String) -> [Substring] {
        text.replacingOccurrences(of: missingTranscriptionMarker, with: " ")
            .split(whereSeparator: \.isWhitespace)
    }

    private static func keywords(in turns: [SpeakerTurn]) -> [Keyword] {
        var counts: [String: Int] = [:]
        var display: [String: String] = [:]
        for turn in turns {
            let cleaned = turn.text.replacingOccurrences(of: missingTranscriptionMarker, with: " ")
            for token in cleaned.lowercased().split(whereSeparator: { !$0.isLetter }) where token.count >= 4 {
                let folded = token.folding(options: .diacriticInsensitive, locale: nil)
                guard !stopWords.contains(folded) else { continue }
                counts[folded, default: 0] += 1
                if display[folded] == nil { display[folded] = String(token) }
            }
        }
        return counts
            .filter { $0.value >= 2 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(maxKeywords)
            .map { Keyword(word: display[$0.key] ?? $0.key, count: $0.value) }
    }

    /// Mots vides fr/en de 4 lettres et plus, sans accents (comparés après
    /// repli des diacritiques). Volontairement modeste : pas de NLP.
    private static let stopWords: Set<String> = [
        // français
        "alors", "aussi", "assez", "autre", "autres", "avant", "avec", "avez", "avoir", "bien", "cela",
        "celle", "celui", "cette", "ceux", "chaque", "comme", "comment", "dans", "donc", "dont", "elle",
        "elles", "encore", "entre", "etait", "etre", "faire", "fait", "faut", "leur", "leurs", "mais",
        "meme", "moins", "mon", "nous", "notre", "nos", "parce", "pour", "pourquoi", "quand",
        "que", "quel", "quelle", "quels", "sans", "sera", "sont", "sous", "suis", "tout", "tous",
        "toute", "toutes", "tres", "trop", "votre", "vous", "vers", "voila", "voir", "peut", "plus",
        "puis", "quoi", "rien", "sais", "sait", "soit", "ensuite", "enfin", "genre", "deja",
        "ouais", "oui", "non", "ben", "bah", "euh", "peux", "veux", "vais", "vont", "avons", "avait",
        "aura", "ces", "ses", "tes", "mes", "lui", "eux", "ici", "ceci", "dire", "dit", "mets",
        "pense", "pensez", "chose", "choses", "juste", "vraiment", "quand", "ainsi", "depuis",
        // anglais
        "about", "after", "again", "also", "because", "been", "before", "being", "could", "does",
        "doing", "done", "each", "from", "have", "having", "here", "into", "just", "like", "make",
        "many", "more", "most", "much", "only", "other", "over", "really", "said", "same", "should",
        "some", "such", "than", "that", "their", "them", "then", "there", "these", "they", "thing",
        "things", "think", "this", "those", "through", "very", "want", "were", "what", "when", "where",
        "which", "while", "will", "with", "would", "your", "yeah", "okay", "gonna", "going", "know",
    ]
}
