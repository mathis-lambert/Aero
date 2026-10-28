import Foundation
import Testing
@testable import BrowserCore

// docs/BROWSING.md › Pinned pages. Written as failure modes first:
// 1. Browsing in a favorite replaces the page it was pinned on.
// 2. An open tab keeps a pinned page, or a favorite loses its own when it moves, changes space or profile.
// 3. A fragment or a trailing slash counts as leaving the pinned page, or a terminal's folder does.
// 4. Going back, or replacing the pinned page, changes an open tab or accepts an address no tab shows.
// 5. A favorite without its own page passes validation.

private func favorite() throws -> (BrowserSession, UUID) {
    var session = BrowserSession(profileName: "Personal")
    let opened = session.open(URL(string: "https://example.test/home")!, in: session.spaces[0].id)
    let tab = try #require(opened)
    _ = session.move(id: tab.id, to: .grid, before: nil)
    return (session, tab.id)
}

@Test func browsingInAFavoriteKeepsItsPinnedPage() throws {
    var (session, id) = try favorite()
    let home = URL(string: "https://example.test/home")!
    #expect(session.tabs[0].pinnedURL == home)
    session.updateTab(id: id, url: URL(string: "https://example.test/home/#top")!, title: "Home")
    #expect(!session.tabs[0].hasLeftPinnedPage, "A fragment or a trailing slash is the same page")
    session.updateTab(id: id, url: URL(string: "https://example.test/article")!, title: "Article")
    #expect(session.tabs[0].pinnedURL == home && session.tabs[0].hasLeftPinnedPage)

    session.returnToPinnedPage(id: id)
    #expect(session.tabs[0].url == home && !session.tabs[0].hasLeftPinnedPage)
    try session.validate()
}

@Test func onlyFavoritesHaveAPinnedPageAndKeepItWhereverTheyGo() throws {
    var (session, id) = try favorite()
    let home = URL(string: "https://example.test/home")!
    session.updateTab(id: id, url: URL(string: "https://example.test/article")!, title: "Article")
    _ = session.move(id: id, to: .list(group: nil), before: nil)
    #expect(session.tabs[0].pinnedURL == home, "Moving among the favorites keeps it")

    let other = try session.addProfile(name: "Work")
    let work = try session.addSpace(name: "Work", profileID: other.id, color: .initial)
    let transferred = session.transfer(id: id, to: work.id)
    let moved = try #require(transferred[id])
    #expect(session.tabs.first { $0.id == moved }?.pinnedURL == home, "A new identity keeps it")

    _ = session.move(id: moved, to: .open, before: nil)
    #expect(session.tabs.first { $0.id == moved }?.pinnedURL == nil, "An open tab has none")
    _ = session.move(id: moved, to: .grid, before: nil)
    #expect(session.tabs.first { $0.id == moved }?.pinnedURL == URL(string: "https://example.test/article"), "Pinned again, on its page")
    try session.validate()
}

@Test func thePinnedPageIsReplacedOnlyForAFavoriteAndAnAddressATabShows() throws {
    var (session, id) = try favorite()
    let current = URL(string: "https://example.test/current")!
    let replaced = session.setPinnedURL(id: id, to: current)
    #expect(replaced && session.tabs[0].pinnedURL == current)
    let script = session.setPinnedURL(id: id, to: URL(string: "javascript:alert(1)")!)
    #expect(!script, "An address no tab shows is refused")
    let opened = session.open(current, in: session.spaces[0].id)
    let open = try #require(opened)
    let ofOpenTab = session.setPinnedURL(id: open.id, to: current)
    #expect(!ofOpenTab, "An open tab has no pinned page")
    try session.validate()
}

@Test func aFavoriteWithoutItsPinnedPageFailsValidation() throws {
    let (session, _) = try favorite()
    var tab = session.tabs[0]
    tab.pinnedURL = nil
    let broken = BrowserSession(profiles: session.profiles, spaces: session.spaces, tabs: [tab])
    #expect(throws: SessionError.inconsistentData) { try broken.validate() }
}

@Test func aTerminalNeverLeavesItsPinnedPage() throws {
    var session = BrowserSession(profileName: "Personal")
    let terminal = URL(string: "aero://terminal?dir=/Users")!
    let opened = session.open(terminal, in: session.spaces[0].id)
    let tab = try #require(opened)
    _ = session.move(id: tab.id, to: .grid, before: nil)
    session.updateTab(id: tab.id, url: URL(string: "aero://terminal?dir=/tmp")!, title: "zsh")
    #expect(!session.tabs[0].hasLeftPinnedPage, "A shell's folder is not another page")
    session.updateTab(id: tab.id, url: URL(string: "https://example.test")!, title: "Example")
    #expect(session.tabs[0].hasLeftPinnedPage)
}
