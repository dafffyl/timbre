//
//  MarkdownReportText.swift
//  Timbre
//

import SwiftUI

/// Rendu minimal d'un rapport en Markdown : titres, puces, paragraphes, et
/// le Markdown « en ligne » (gras, italique) géré par `AttributedString`.
/// `Text` seul ne rend pas les blocs (titres, listes) : ils s'affichaient
/// avec leurs `##` et `-` bruts.
struct MarkdownReportText: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(markdown.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                lineView(line)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func lineView(_ raw: String) -> some View {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty {
            EmptyView()
        } else if let heading = Self.heading(in: line) {
            inline(heading.text)
                .font(heading.level <= 1 ? .timbreTitle(22) : .timbreTitle(17))
                .foregroundStyle(Color.timbreTextPrimary)
                .padding(.top, 6)
        } else if let bullet = Self.bullet(in: line) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(bullet.marker)
                    .foregroundStyle(Color.timbreViolet)
                inline(bullet.text)
            }
            .font(.timbreBody(15))
            .foregroundStyle(Color.timbreTextPrimary)
        } else {
            inline(line)
                .font(.timbreBody(15))
                .foregroundStyle(Color.timbreTextPrimary)
        }
    }

    private func inline(_ text: String) -> Text {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attributed = try? AttributedString(markdown: text, options: options) {
            return Text(attributed)
        }
        return Text(text)
    }

    static func heading(in line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }
        guard !hashes.isEmpty, hashes.count <= 6, line.dropFirst(hashes.count).first == " " else { return nil }
        return (hashes.count, String(line.dropFirst(hashes.count + 1)))
    }

    static func bullet(in line: String) -> (marker: String, text: String)? {
        for prefix in ["- ", "* ", "• "] where line.hasPrefix(prefix) {
            return ("•", String(line.dropFirst(prefix.count)))
        }
        // Liste numérotée : « 1. texte » / « 1) texte ».
        let digits = line.prefix { $0.isNumber }
        if !digits.isEmpty, digits.count <= 2 {
            let rest = line.dropFirst(digits.count)
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") {
                return ("\(digits).", String(rest.dropFirst(2)))
            }
        }
        return nil
    }
}
