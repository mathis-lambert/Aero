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
struct ControlBarPresentation: Identifiable {
    let id = UUID()
    let target: ControlBarTarget
    let initialText: String
}

/// One row of results. See docs/CONTROL_BAR.md › Behavior for their order.
enum ControlBarItem: Equatable {
    case open(URL)
    case search(String)
    case suggestion(String)
    case tab(BrowserTab)
    case history(HistoryEntry)
    case command(BrowserCommand)
}

/// The text, results and selection of one control bar. Suggestions and history arrive
/// asynchronously; only the latest text may update them.
@MainActor @Observable
final class ControlBarModel {
    /// Waits for a pause in typing before asking the engine and the history.
    private static let typingPause = Duration.milliseconds(120)
    private static let maximumTabs = 3
    private static let maximumHistory = 3

    let target: ControlBarTarget
    /// Over a tab rather than on the New Tab page. With no text, it lists the commands and doubles
    /// as the shortcut reference; the New Tab page shows no list until you type.
    let isOverlay: Bool
    var text: String {
        didSet { if text != oldValue { selection = 0 } }
    }
    private(set) var selection = 0
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
        guard !query.isEmpty else { return isOverlay ? commands(matching: nil) : [] }
        let go: ControlBarItem = NavigationInput.address(from: query).map(ControlBarItem.open) ?? .search(query)
        let tabs = browser.tabs
        let openURLs = Set(tabs.map(\.url))
        return [go]
            + suggestions.map(ControlBarItem.suggestion)
            + openTabs(tabs, matching: query).map(ControlBarItem.tab)
            + history.filter { !openURLs.contains($0.url) }.prefix(Self.maximumHistory).map(ControlBarItem.history)
            + commands(matching: query)
    }

    /// The highlighted row of `items`, kept inside the list as it shrinks.
    func selectedIndex(in items: [ControlBarItem]) -> Int? {
        items.isEmpty ? nil : min(selection, items.count - 1)
    }

    func select(_ index: Int) { selection = index }

    func moveSelection(by offset: Int) {
        let items = items
        guard let index = selectedIndex(in: items) else { return }
        selection = min(max(index + offset, 0), items.count - 1)
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

    /// Runs for each text, from the view's task: a newer text cancels it before it updates anything.
    func refresh() async {
        let query = query
        guard !query.isEmpty else {
            suggestions = []
            history = []
            return
        }
        do { try await Task.sleep(for: Self.typingPause) } catch { return }
        async let suggested = suggestions(for: query)
        async let visited = visits(matching: query)
        let (newSuggestions, newHistory) = await (suggested, visited)
        guard !Task.isCancelled else { return }
        suggestions = newSuggestions
        history = newHistory
    }

    /// Never sends text that looks like an address, and nothing while suggestions are off.
    private func suggestions(for query: String) async -> [String] {
        guard browser.preferences.searchSuggestions, !NavigationInput.looksLikeAddress(query),
              let url = browser.webSearch.suggestionsURL(for: query) else { return [] }
        return await browser.suggestionFetcher.suggestions(from: url, for: query)
    }

    /// Asks for extra entries so that pages already open can be left out.
    private func visits(matching query: String) async -> [HistoryEntry] {
        guard let profileID = browser.window.selectedProfileID else { return [] }
        let limit = Self.maximumHistory + Self.maximumTabs
        // Best effort: an unavailable history only leaves its rows out.
        return (try? await browser.history.entries(profileID: profileID, matching: query, limit: limit)) ?? []
    }

    /// Other tabs of the space whose title or address matches.
    private func openTabs(_ tabs: [BrowserTab], matching query: String) -> [BrowserTab] {
        let selectedID = browser.window.selectedTabID
        let matches = tabs.lazy.filter { tab in
            tab.id != selectedID
                && (tab.displayTitle.localizedStandardContains(query) || tab.url.absoluteString.localizedStandardContains(query))
        }
        return Array(matches.prefix(Self.maximumTabs))
    }

    private func commands(matching query: String?) -> [ControlBarItem] {
        BrowserCommand.allCases
            .filter { command in
                command != .commandPalette && browser.isEnabled(command)
                    && (query.map(command.title.localizedStandardContains) ?? true)
            }
            .map(ControlBarItem.command)
    }
}
