import BrowserCore
import Foundation
import Observation

/// Where the arrow keys are on the shelf while the field keeps the keyboard focus; `nil` is the field.
enum ShelfFocus: Equatable {
    case site(Int)
    case closed(Int)
}

/// An arrow key, in reading order: `previous` and `next` follow the layout direction.
enum ShelfMove {
    case up, down, previous, next
}

extension ShelfFocus? {
    /// Down enters the shelf and goes from the sites to the closed tabs; up goes back toward the field.
    /// Moves stop at the ends of a row, and a row keeps the column as near as it has.
    func moved(_ move: ShelfMove, sites: Int, closed: Int) -> ShelfFocus? {
        switch (self?.clamped(sites: sites, closed: closed), move) {
        case (nil, .down): sites > 0 ? .site(0) : closed > 0 ? .closed(0) : nil
        case (nil, _): nil
        case (.site?, .up): nil
        case (.site(let index)?, .down): closed > 0 ? .closed(min(index, closed - 1)) : .site(index)
        case (.site(let index)?, .previous): .site(Swift.max(index - 1, 0))
        case (.site(let index)?, .next): .site(Swift.min(index + 1, sites - 1))
        case (.closed(let index)?, .up): sites > 0 ? .site(Swift.min(index, sites - 1)) : nil
        case (.closed(let index)?, .down): .closed(index)
        case (.closed(let index)?, .previous): .closed(Swift.max(index - 1, 0))
        case (.closed(let index)?, .next): .closed(Swift.min(index + 1, closed - 1))
        }
    }
}

extension ShelfFocus {
    /// The same place once its row has shrunk; `nil` once the row is empty.
    func clamped(sites: Int, closed: Int) -> ShelfFocus? {
        switch self {
        case .site(let index): sites > 0 ? .site(Swift.min(index, sites - 1)) : nil
        case .closed(let index): closed > 0 ? .closed(Swift.min(index, closed - 1)) : nil
        }
    }
}

/// The New Tab page's frequent sites and recently closed tabs, read once as the page appears. See
/// docs/BROWSING.md › New Tab.
@MainActor @Observable
final class NewTabShelf {
    private static let siteLimit = 6
    private static let closedLimit = 3
    /// Enough visits for a month of habits, few enough to rank in a few milliseconds.
    private static let visitLimit = 4000
    /// Ranked beyond what shows, so hiding a site brings the next one at once.
    private static let rankedLimit = 12

    private(set) var closed: [BrowserTab] = []
    private(set) var focus: ShelfFocus?
    private var ranked: [FrequentSites.Site] = []
    @ObservationIgnored private let browser: BrowserModel
    @ObservationIgnored private let profileID: UUID?

    init(browser: BrowserModel) {
        self.browser = browser
        profileID = browser.profile?.id
    }

    var sites: [FrequentSites.Site] {
        let hidden = profileID.flatMap { browser.preferences.hiddenNewTabSites[$0] } ?? []
        return Array(ranked.lazy.filter { !hidden.contains($0.key) }.prefix(Self.siteLimit))
    }

    func load() async {
        let spaceID = browser.space?.id
        var seen = Set<URL>()
        closed = Array(browser.closedTabs.reversed().lazy.filter { $0.spaceID == spaceID && seen.insert($0.url).inserted }.prefix(Self.closedLimit))
        guard let profileID else { return }
        let now = Date.now
        // Best effort: without history, the page only leaves its sites out.
        guard let visits = try? await browser.history.recentVisits(profileID: profileID, since: now - FrequentSites.period, limit: Self.visitLimit),
              !Task.isCancelled else { return }
        // The favorites are a click away in the sidebar already.
        let favorites = Set(browser.tabs.filter(\.isFavorite).compactMap { FrequentSites.key(for: $0.url) })
        let limit = Self.rankedLimit
        let ranked = await Task.detached(priority: .userInitiated) {
            FrequentSites.rank(visits, at: now, excluding: favorites, limit: limit)
        }.value
        guard !Task.isCancelled else { return }
        self.ranked = ranked
        clampFocus()
    }

    func move(_ move: ShelfMove) {
        focus = focus.moved(move, sites: sites.count, closed: closed.count)
    }

    func clearFocus() { focus = nil }

    /// Opens what the arrows reached; `false` when they are on the field.
    func activateFocus() -> Bool {
        switch focus?.clamped(sites: sites.count, closed: closed.count) {
        case .site(let index): open(sites[index])
        case .closed(let index): reopen(closed[index])
        case nil: return false
        }
        return true
    }

    /// A site already open in the space is switched to rather than opened again.
    func open(_ site: FrequentSites.Site) {
        if let tab = browser.tabs.first(where: { $0.url == site.url }) { browser.showTab(tab) }
        else { browser.load(site.url, in: .newTab) }
    }

    func reopen(_ tab: BrowserTab) { browser.reopenTab(tab.id) }

    func hide(_ site: FrequentSites.Site) {
        guard let profileID else { return }
        browser.preferences.hideNewTabSite(site.key, in: profileID)
        clampFocus()
    }

    private func clampFocus() {
        focus = focus?.clamped(sites: sites.count, closed: closed.count)
    }
}
