@testable import Aero
import BrowserCore
import Foundation
import Testing

// docs/BROWSING.md › Control bar. Written as failure modes first:
// 1. A command typed with its own words ("capture portrait") stays under the engine's search.
// 2. A site visited often stays under the search row and the suggestions.
// 3. A suggestion outranks the search row, or an address typed in full is not first.
// 4. With nothing local matching, the search row is not first, or suggestions lose the engine's order.
// 5. The shown tab is offered, or a page open in a tab also shows as history.
// 6. One kind fills the list past its share.

struct ControlBarResultsTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let space = UUID()

    private func tab(_ title: String, _ address: String) -> BrowserTab {
        BrowserTab(spaceID: space, url: URL(string: address)!, title: title)
    }

    private func visit(_ id: Int64, _ title: String, _ address: String, visits: Int, daysAgo: Double = 1) -> HistoryEntry {
        HistoryEntry(id: id, url: URL(string: address)!, title: title, lastVisit: now.addingTimeInterval(-daysAgo * 86_400), visitCount: visits)
    }

    private func rank(_ text: String, tabs: [BrowserTab] = [], shown: UUID? = nil, history: [HistoryEntry] = [],
                      commands: [BrowserCommand] = BrowserCommand.allCases, suggestions: [String] = []) -> [String] {
        ControlBarResults.rank(text, tabs: tabs, shownTabID: shown, history: history, commands: commands,
                               suggestions: suggestions, now: now).map(\.id)
    }

    @Test func aCommandTypedWithItsWordsComesFirst() {
        let rows = rank("capture portrait", suggestions: ["capture portrait mode iphone"])
        #expect(rows.prefix(2) == ["command.capturePortrait", "search.capture portrait"])
        #expect(rows.last == "suggestion.capture portrait mode iphone")
    }

    @Test func aSiteVisitedOftenComesBeforeTheSearch() {
        let github = visit(1, "GitHub", "https://github.com/", visits: 40)
        let digital = visit(2, "Digital garden", "https://digital.example/", visits: 1, daysAgo: 60)
        let rows = rank("git", history: [digital, github], commands: [], suggestions: ["github", "git commands"])
        #expect(rows == ["history.1", "search.git", "suggestion.git commands", "suggestion.github", "history.2"],
                "The host typed from its start goes first; suggestions follow the search row, the closest first; a fragment inside a word comes last")
    }

    @Test func anAddressComesFirstAndSuggestionsKeepTheEnginesOrder() {
        #expect(rank("example.com", history: [visit(1, "Example", "https://example.com/", visits: 9)]).first == "open.https://example.com")
        let rows = rank("zebra crossing", commands: [], suggestions: ["zebra crossing rules", "zebra"])
        #expect(rows == ["search.zebra crossing", "suggestion.zebra crossing rules", "suggestion.zebra"])
    }

    @Test func openTabsReplaceTheirHistoryAndTheShownTabIsLeftOut() {
        let mail = tab("Inbox — Mail", "https://mail.example/")
        let docs = tab("Docs", "https://docs.example/")
        let rows = rank("mail", tabs: [mail, docs], shown: docs.id, history: [visit(1, "Inbox", "https://mail.example/", visits: 50)], commands: [])
        #expect(rows == ["tab.\(mail.id)", "search.mail"])
        #expect(!rank("docs", tabs: [mail, docs], shown: docs.id, commands: []).contains("tab.\(docs.id)"))
    }

    @Test func eachKindKeepsToItsShare() {
        let history = (1...9).map { visit(Int64($0), "Swift page \($0)", "https://swift.example/\($0)", visits: $0) }
        let rows = rank("swift", history: history, commands: [], suggestions: (1...9).map { "swift \($0)" })
        #expect(rows.count { $0.hasPrefix("history.") } == ControlBarResults.maximumHistory)
        #expect(rows.count { $0.hasPrefix("suggestion.") } == ControlBarResults.maximumSuggestions)
        #expect(rows.first == "history.9", "The most visited of the equally matching pages")
    }
}
