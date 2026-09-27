import Foundation
import Testing
@testable import BrowserCore

@Test func staleMetadataCannotResurrectClosedTabs() throws {
    var session = BrowserSession(profileName: "Personal")
    let space = try #require(session.spaces.first)
    let url = try #require(URL(string: "https://example.com"))
    let result = session.open(url, in: space.id)
    let tab = try #require(result)
    session.close(id: tab.id)
    session.updateTab(id: tab.id, url: url, title: "Late event")
    #expect(session.tabs.isEmpty)
    session.restore(tab)
    session.restore(tab)
    #expect(session.tabs.count == 1)
}

// Invalid emoji must not become a space icon (docs/SPACES.md).
@Test func spaceEmojiIsExactlyOneEmoji() {
    for emoji in ["🚀", "❤️", "🇫🇷", "👩‍👩‍👧", "👍🏽", "1️⃣", " 🌿 "] {
        #expect(BrowserSpace.emoji(from: emoji) == emoji.trimmingCharacters(in: .whitespaces), "\(emoji)")
    }
    for text in ["", " ", "a", "Work", "1", "#", "🚀🌿", "🚀a", "\u{1F3FD}", "\u{FE0F}", "❤"] {
        #expect(BrowserSpace.emoji(from: text) == nil, "\(text)")
    }
}

@Test func spacesValidateIdentityAndAppearance() throws {
    var session = BrowserSession(profileName: "Personal")
    let profile = try session.addProfile(name: "Work")
    let space = try session.addSpace(name: "Work", profileID: profile.id, color: .initial, emoji: "🚀")
    try session.validate()
    #expect(throws: SessionError.invalidEmoji) {
        try session.editSpace(id: space.id, name: "Work", profileID: profile.id, color: .initial, emoji: "Work")
    }
    #expect(throws: SessionError.profileInUse) { try session.markProfileForRemoval(profile.id) }
    let other = try session.addSpace(name: "Other", profileID: profile.id, color: .initial)
    try session.removeSpace(space.id)
    try session.removeSpace(other.id)
    try session.markProfileForRemoval(profile.id)
    try session.removeProfile(profile.id)
    #expect(throws: SessionError.lastSpace) { try session.removeSpace(session.spaces[0].id) }
    #expect(throws: SessionError.lastProfile) { try session.markProfileForRemoval(session.profiles[0].id) }
    try session.validate()
}

// Reject cross-space placement and references to foreign groups.
@Test func tabsStayInTheirSpaceAndItsGroups() throws {
    var session = BrowserSession(profileName: "Personal")
    let personal = try #require(session.spaces.first)
    let workProfile = try session.addProfile(name: "Work")
    try session.addSpace(name: "Work", profileID: workProfile.id, color: .initial)
    let work = try #require(session.spaces.last)
    let url = try #require(URL(string: "https://example.com"))
    let opened = (session.open(url, in: personal.id), session.open(url, in: work.id), session.addGroup(named: "Reading", in: work.id))
    let mine = try #require(opened.0)
    let theirs = try #require(opened.1)
    let group = try #require(opened.2)

    let moves = [session.move(id: mine.id, to: .list(group: group.id), before: nil),
                 session.move(id: mine.id, to: .grid, before: theirs.id),
                 session.move(id: theirs.id, to: .list(group: UUID()), before: nil),
                 session.move(id: theirs.id, to: .list(group: group.id), before: nil)]
    // Into another space's group, before another space's tab, into a group that does not exist.
    #expect(moves == [false, false, false, true])

    var invalid = session.spaces
    invalid[1].groups = []
    let decoded = BrowserSession(profiles: session.profiles, spaces: invalid, tabs: session.tabs)
    #expect(throws: SessionError.inconsistentData) { try decoded.validate() }

    session.removeGroup(id: group.id)
    #expect(session.tabs.first { $0.id == theirs.id }?.place == .list(group: nil), "Ungrouping keeps the favorite")
    try session.validate()
}
