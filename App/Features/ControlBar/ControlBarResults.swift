import BrowserCore
import Foundation

/// The control bar's rows for one query, ranked together: commands, open tabs, visited pages and the engine's
/// suggestions mix by `ResultRanking`'s score, around the search row. An address typed in full always comes first.
/// See docs/BROWSING.md › Control bar.
enum ControlBarResults {
    static let maximumTabs = 3
    static let maximumHistory = 4
    static let maximumCommands = 4
    static let maximumSuggestions = 4

    /// `text` is trimmed. `tabs` are the space's tabs: the shown one is not offered, and pages open in any of them
    /// leave the history. `isAvailable` is asked only of the commands that match.
    static func rank(_ text: String, tabs: [BrowserTab], shownTabID: UUID?, history: [HistoryEntry], commands: [BrowserCommand],
                     isAvailable: (BrowserCommand) -> Bool, suggestions: [String], now: Date) -> [ControlBarItem] {
        let query = ResultRanking.Query(text)
        let openURLs = Set(tabs.map(\.url))
        let tabRows = best(tabs.filter { $0.id != shownTabID }, maximumTabs) { tab in
            ResultRanking.match(query, title: tab.displayTitle, address: tab.url).map { $0 + ResultRanking.tabBonus }
        }
        let commandRows = best(commands, maximumCommands) { command in command.searchScore(query).flatMap { isAvailable(command) ? $0 : nil } }
        let historyRows = best(history.filter { !openURLs.contains($0.url) }, maximumHistory) { entry in
            ResultRanking.match(query, title: entry.title, address: entry.url)
                .map { $0 + ResultRanking.historyBonus(visitCount: entry.visitCount, lastVisit: entry.lastVisit, now: now) }
        }
        // The engine may suggest words the query does not have; they still go under the search row. Suggestions kept
        // from earlier text may repeat what is typed now, which the search row already offers.
        let suggestionRows = suggestions.filter { ResultRanking.Query($0).words != query.words }.prefix(maximumSuggestions).map { suggestion in
            (ControlBarItem.suggestion(suggestion), (ResultRanking.match(query, title: suggestion) ?? 0) * ResultRanking.suggestionWeight)
        }
        let local = tabRows.map { (ControlBarItem.tab($0.0), $0.1) }
            + commandRows.map { (ControlBarItem.command($0.0), $0.1) }
            + historyRows.map { (ControlBarItem.history($0.0), $0.1) }
        if let url = NavigationInput.address(from: text) {
            return [.open(url)] + byScore(local + suggestionRows).map(\.0)
        }
        return byScore(local + [(.search(text), ResultRanking.searchScore)] + suggestionRows).map(\.0)
    }

    /// The `limit` best-scored of `candidates` that match.
    private static func best<Candidate>(_ candidates: [Candidate], _ limit: Int, score: (Candidate) -> Double?) -> [(Candidate, Double)] {
        Array(byScore(candidates.compactMap { candidate in score(candidate).map { (candidate, $0) } }).prefix(limit))
    }

    /// Higher scores first; equal ones keep their order, which `rank` sets: tabs, commands, history, the search row,
    /// suggestions.
    private static func byScore<Row>(_ rows: [(Row, Double)]) -> [(Row, Double)] {
        rows.enumerated().sorted { $0.element.1 != $1.element.1 ? $0.element.1 > $1.element.1 : $0.offset < $1.offset }.map(\.element)
    }
}
