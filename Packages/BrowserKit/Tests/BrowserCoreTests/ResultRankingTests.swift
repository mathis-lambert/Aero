import Foundation
import Testing
@testable import BrowserCore

// docs/BROWSING.md › Control bar. Written as failure modes first:
// 1. Words typed out of the title's order, or with a word between them, find nothing ("capture portrait").
// 2. Accents, case or a `www.` decide whether a result matches.
// 3. A word found nowhere still lets the result through, or a two-letter fragment matches inside any word.
// 4. A strong local match stays under the search row, or a weak one goes above it.
// 5. Engine suggestions outrank the search row however well they match.
// 6. A page visited often, or just now, gains nothing; or visits make an unrelated page outrank a real match.

struct ResultRankingTests {
    private func match(_ text: String, title: String, aliases: [String] = [], address: String? = nil) -> Double? {
        ResultRanking.match(.init(text), title: title, aliases: aliases, address: address.flatMap(URL.init(string:)))
    }

    @Test func everyWordStartsAWordInAnyOrder() throws {
        let portrait = try #require(match("capture portrait", title: "Capture in Portrait Mode"))
        #expect(portrait >= ResultRanking.searchScore, "Whole words of the title, around another one")
        #expect(match("portrait capture", title: "Capture in Portrait Mode") != nil, "In any order")
        let started = try #require(match("cap port", title: "Capture in Portrait Mode"))
        #expect(started >= ResultRanking.searchScore, "Word starts are enough to go above the search row")
        #expect(match("capture video", title: "Capture in Portrait Mode") == nil, "A word found nowhere excludes it")
        #expect(match("screenshot", title: "Capture in Portrait Mode", aliases: ["screenshot picture image"]) != nil, "Aliases count as names")
    }

    @Test func accentsCaseAndWWWDoNotMatter() {
        #expect(match("ETE", title: "Été à Lyon") != nil)
        #expect(match("préférences", title: "Preferences") != nil)
        let host = match("github", title: "Some repository", address: "https://www.github.com/mathis/aero")
        let path = match("aero", title: "Some repository", address: "https://www.github.com/mathis/aero")
        #expect(host.map { $0 >= ResultRanking.searchScore } == true, "The host typed from its start, without www.")
        #expect(path != nil, "Words of the path count too")
    }

    @Test func fragmentsInsideWordsCountLittle() throws {
        let inside = try #require(match("tube", title: "YouTube"))
        #expect(inside < ResultRanking.searchScore, "Found inside a word, it stays under the search row")
        #expect(match("ou", title: "YouTube") == nil, "Too short to match inside a word")
        let leading = try #require(match("you", title: "YouTube"))
        #expect(leading > inside, "The start of the title counts more than its inside")
    }

    @Test func suggestionsStayUnderTheSearchRow() throws {
        let best = try #require(match("swift concurrency", title: "swift concurrency"))
        #expect(best * ResultRanking.suggestionWeight < ResultRanking.searchScore)
    }

    @Test func visitsLiftAMatchWithoutReplacingIt() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let never = ResultRanking.historyBonus(visitCount: 0, lastVisit: now.addingTimeInterval(-365 * 86_400), now: now)
        let daily = ResultRanking.historyBonus(visitCount: 60, lastVisit: now.addingTimeInterval(-3_600), now: now)
        let monthAgo = ResultRanking.historyBonus(visitCount: 60, lastVisit: now.addingTimeInterval(-30 * 86_400), now: now)
        #expect(never < 0.01)
        #expect(daily > monthAgo && monthAgo > never, "Frequent and recent visits count, recency fading")
        #expect(daily <= ResultRanking.frequencyBonus + ResultRanking.recencyBonus, "Bounded, however many visits")
        #expect(ResultRanking.historyBonus(visitCount: 1_000_000, lastVisit: now, now: now) <= 0.5)
        #expect(ResultRanking.historyBonus(visitCount: 5, lastVisit: now.addingTimeInterval(60), now: now) <= 0.5, "A clock moved back counts as now")
    }

    @Test func anEmptyQueryMatchesNothing() {
        #expect(match("  ", title: "Anything") == nil)
        #expect(match("%%", title: "100% zoom") == nil, "Punctuation alone is not a word")
    }
}
