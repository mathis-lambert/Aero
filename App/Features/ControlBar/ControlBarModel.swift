import BrowserCore
import Foundation
import Observation

/// Where the control bar opens what you choose.
enum ControlBarTarget {
    /// Replaces the page of the selected tab, or opens a tab from the New Tab page.
    case currentTab
    case newTab
}

/// The control bar shown over the selected tab. The New Tab page hosts its own bar instead.
struct ControlBarPresentation {
    let id = UUID()
    let target: ControlBarTarget
    let initialText: String
}

/// One row of results, ranked by `ControlBarResults`. See docs/BROWSING.md › Control bar.
enum ControlBarItem {
    case open(URL)
    case search(String)
    case suggestion(String)
    case tab(BrowserTab)
    case history(HistoryEntry)
    case command(BrowserCommand)

    /// The same row across rankings, so the selection stays on it when results arrive.
    var id: String {
        switch self {
        case .open(let url): "open.\(url.absoluteString)"
        case .search(let query): "search.\(query)"
        case .suggestion(let suggestion): "suggestion.\(suggestion)"
        case .tab(let tab): "tab.\(tab.id)"
        case .history(let entry): "history.\(entry.id)"
        case .command(let command): "command.\(command.rawValue)"
        }
    }
}

/// The text, results and selection of one control bar. Suggestions and history arrive
/// asynchronously; only the latest text may update them.
@MainActor @Observable
final class ControlBarModel {
    /// Waits for a pause in typing before asking the engine; the history, on this Mac, answers at once.
    private static let typingPause = Duration.milliseconds(120)
    /// Visited pages to rank, most visited first, so pages already open can be left out.
    private static let historyCandidates = 24

    let target: ControlBarTarget
    /// Over a tab rather than on the New Tab page. With no text, it lists the commands and doubles
    /// as the shortcut reference; the New Tab page shows no list until you type.
    let isOverlay: Bool
    var text: String {
        didSet { if text != oldValue { chosen = nil } }
    }
    /// The row moved to with the arrows or the pointer; until then the selection is the first row, whichever it
    /// becomes as results arrive.
    private var chosen: String?
    private(set) var suggestions: [String] = []
    private(set) var history: [HistoryEntry] = []
    @ObservationIgnored private let browser: BrowserModel

    init(browser: BrowserModel, presentation: ControlBarPresentation?) {
        self.browser = browser
        target = presentation?.target ?? .currentTab
        isOverlay = presentation != nil
        text = presentation?.initialText ?? ""
    }

    private var query: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var items: [ControlBarItem] {
        let query = query
        guard !query.isEmpty else { return isOverlay ? availableCommands.map(ControlBarItem.command) : [] }
        return ControlBarResults.rank(query, tabs: browser.tabs, shownTabID: browser.window.selectedTabID, history: history,
                                      commands: availableCommands, suggestions: suggestions, now: .now)
    }

    /// The highlighted row of `items`: the row chosen while it is listed, else the first.
    func selectedIndex(in items: [ControlBarItem]) -> Int? {
        guard !items.isEmpty else { return nil }
        return chosen.flatMap { id in items.firstIndex { $0.id == id } } ?? 0
    }

    func select(_ index: Int) {
        let items = items
        if items.indices.contains(index) { chosen = items[index].id }
    }

    func moveSelection(by offset: Int) {
        let items = items
        guard let index = selectedIndex(in: items) else { return }
        chosen = items[min(max(index + offset, 0), items.count - 1)].id
    }

    func activateSelection() {
        let items = items
        guard let index = selectedIndex(in: items) else { return }
        activate(items[index])
    }

    func activate(_ item: ControlBarItem) {
        switch item {
        case .open(let url): browser.load(url, in: target)
        case .search(let query), .suggestion(let query):
            if let url = browser.webSearch.searchURL(for: query) { browser.load(url, in: target) }
        case .tab(let tab):
            browser.window.controlBar = nil
            browser.selectTab(tab.id)
        case .history(let entry): browser.load(entry.url, in: target)
        case .command(let command):
            browser.window.controlBar = nil
            browser.perform(command)
        }
        text = ""
    }

    /// Runs for each text, from the view's task: a newer text cancels it before it updates anything. The previous
    /// results stay, ranked against the new text, until the new ones replace them.
    func refresh() async {
        let query = query
        guard !query.isEmpty else {
            suggestions = []
            history = []
            return
        }
        async let visited: Void = refreshHistory(for: query)
        async let suggested: Void = refreshSuggestions(for: query)
        _ = await (visited, suggested)
    }

    private func refreshSuggestions(for query: String) async {
        do { try await Task.sleep(for: Self.typingPause) } catch { return }
        let results = await suggestions(for: query)
        guard !Task.isCancelled, self.query == query else { return }
        suggestions = results
    }

    private func refreshHistory(for query: String) async {
        let results = await visits(matching: query)
        guard !Task.isCancelled, self.query == query else { return }
        history = results
    }

    /// Never sends text that looks like an address, and nothing while suggestions are off.
    private func suggestions(for query: String) async -> [String] {
        guard browser.preferences.searchSuggestions, !NavigationInput.looksLikeAddress(query),
              let url = browser.webSearch.suggestionsURL(for: query) else { return [] }
        return await browser.suggestionFetcher.suggestions(from: url, for: query)
    }

    private func visits(matching query: String) async -> [HistoryEntry] {
        guard let profileID = browser.profile?.id else { return [] }
        // Best effort: an unavailable history only leaves its rows out.
        return (try? await browser.history.matches(profileID: profileID, query: query, limit: Self.historyCandidates)) ?? []
    }

    private var availableCommands: [BrowserCommand] {
        BrowserCommand.allCases.filter { $0 != .commandPalette && browser.isEnabled($0) }
    }
}
