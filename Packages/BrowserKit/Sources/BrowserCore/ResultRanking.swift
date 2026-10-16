import Foundation

/// How the control bar ranks results of every kind against what was typed: one score, so a command, a tab, a visited
/// page and the engine's suggestions mix by relevance. See docs/BROWSING.md › Control bar.
public enum ResultRanking {
    /// The score of “Search with the engine”: local results that match better go above it.
    public static let searchScore = 0.8
    /// Engine suggestions repeat the query, so they always match well; this keeps them under the search row.
    public static let suggestionWeight = 0.6
    /// An open tab is the quickest way back to a page.
    public static let tabBonus = 0.15
    /// A visited page gains up to this much from how often, and up to `recencyBonus` from how lately, it was visited.
    public static let frequencyBonus = 0.4
    public static let recencyBonus = 0.1
    private static let recencyHalfLife: TimeInterval = 7 * 86_400
    /// A field that starts with the whole query, as a title or a host typed from its start.
    private static let leadingBonus = 0.3
    /// An address matches a little less than a title.
    private static let addressWeight = 0.9
    /// A query word found inside a word, not at its start, counts this much, and only from this length.
    private static let insideScore = 0.4
    private static let insideMinimumLength = 3

    /// The text typed, folded for comparison and split into words.
    public struct Query: Sendable {
        let folded: String
        let words: [String]

        public init(_ text: String) {
            folded = ResultRanking.fold(text).trimmingCharacters(in: .whitespacesAndNewlines)
            words = ResultRanking.words(of: folded)
        }

        public var isEmpty: Bool { words.isEmpty }
    }

    /// How well `query` matches a title and its other names, nil when a word of the query matches none of their
    /// words. Every query word must start a word of the same field, in any order; a whole word counts more than its
    /// start, and a field that starts with the whole query more again.
    public static func match(_ query: Query, title: String, aliases: [String] = [], address: URL? = nil) -> Double? {
        guard !query.isEmpty else { return nil }
        let names = ([title] + aliases).compactMap { score(query, in: fold($0)) }
        let location = address.flatMap { addressText($0) }.flatMap { score(query, in: $0) }.map { $0 * addressWeight }
        return (names + [location].compactMap { $0 }).max()
    }

    /// The bonus of a visited page: more visits count less and less, and older ones fade over weeks.
    public static func historyBonus(visitCount: Int, lastVisit: Date, now: Date) -> Double {
        let frequency = min(1, log2(1 + Double(max(0, visitCount))) / 5) * frequencyBonus
        let age = max(0, now.timeIntervalSince(lastVisit))
        return frequency + exp2(-age / recencyHalfLife) * recencyBonus
    }

    private static func score(_ query: Query, in field: String) -> Double? {
        let fieldWords = words(of: field)
        var total = 0.0
        for word in query.words {
            if fieldWords.contains(word) { total += 1 }
            else if fieldWords.contains(where: { $0.hasPrefix(word) }) { total += 0.85 }
            else if word.count >= insideMinimumLength, field.contains(word) { total += insideScore }
            else { return nil }
        }
        return total / Double(query.words.count) + (field.hasPrefix(query.folded) ? leadingBonus : 0)
    }

    /// The host without `www.`, then the path: what people type of an address.
    private static func addressText(_ url: URL) -> String? {
        guard var host = url.host(percentEncoded: false)?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return fold(host + url.path(percentEncoded: false))
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    private static func words(of text: String) -> [String] {
        text.split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }
}
