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

// The pinned list mixes groups and loose favorites. Failure modes:
// 1. A tab or group cannot go before the other kind, or lands elsewhere.
// 2. Closing, unpinning or moving away a favorite above a group moves the group past others.
// 3. Ungrouping puts the tabs somewhere other than where the group was.
// 4. A group moved to another space loses its tabs' order, their identity within a profile, or its place there.
// 5. An unreadable slot breaks the list instead of reading as the nearest valid one.

private struct PinnedFixture {
    var session = BrowserSession(profileName: "Personal")
    let space: UUID
    var a = UUID(), b = UUID(), c = UUID(), group = UUID(), member = UUID()

    init() throws {
        space = session.spaces[0].id
        func pinned() throws -> UUID {
            let opened = session.open(URL(string: "https://example.com")!, in: space)
            let tab = try #require(opened)
            _ = session.move(id: tab.id, to: .list(group: nil), before: nil)
            return tab.id
        }
        a = try pinned(); b = try pinned(); c = try pinned()
        let added = session.addGroup(named: "Reading", in: space)
        group = try #require(added).id
        let opened = session.open(URL(string: "https://example.com/member")!, in: space)
        let tab = try #require(opened)
        _ = session.move(id: tab.id, to: .list(group: group), before: nil)
        member = tab.id
    }

    var order: [PinnedItem] { session.pinned(in: space) }
}

@Test func groupsAndLooseFavoritesTakeAnyOrder() throws {
    var fixture = try PinnedFixture()
    #expect(fixture.order == [.tab(fixture.a), .tab(fixture.b), .tab(fixture.c), .group(fixture.group)], "A new group comes last")
    let movedGroup = fixture.session.moveGroup(id: fixture.group, before: fixture.b)
    #expect(movedGroup && fixture.order == [.tab(fixture.a), .group(fixture.group), .tab(fixture.b), .tab(fixture.c)])
    let movedTab = fixture.session.move(id: fixture.c, to: .list(group: nil), before: fixture.group)
    #expect(movedTab && fixture.order == [.tab(fixture.a), .tab(fixture.c), .group(fixture.group), .tab(fixture.b)], "A tab goes before a group")
    let fromGroup = fixture.session.move(id: fixture.member, to: .list(group: nil), before: fixture.a)
    #expect(fromGroup && fixture.order.first == .tab(fixture.member), "Out of its group, before the first")
    let refused = fixture.session.move(id: fixture.a, to: .list(group: nil), before: UUID())
    #expect(!refused, "Never before something not in the list")
    try fixture.session.validate()
}

@Test func aGroupKeepsItsPlaceWhenFavoritesAboveItLeave() throws {
    var fixture = try PinnedFixture()
    _ = fixture.session.moveGroup(id: fixture.group, before: fixture.c)
    fixture.session.close(id: fixture.a)
    #expect(fixture.order == [.tab(fixture.b), .group(fixture.group), .tab(fixture.c)], "Closed above it")
    _ = fixture.session.move(id: fixture.b, to: .grid, before: nil)
    #expect(fixture.order == [.group(fixture.group), .tab(fixture.c)], "Moved to the grid")
    _ = fixture.session.move(id: fixture.b, to: .list(group: nil), before: nil)
    #expect(fixture.order == [.group(fixture.group), .tab(fixture.c), .tab(fixture.b)], "Pinned again, last")
}

@Test func ungroupingLeavesItsTabsWhereTheGroupWas() throws {
    var fixture = try PinnedFixture()
    _ = fixture.session.moveGroup(id: fixture.group, before: fixture.b)
    fixture.session.removeGroup(id: fixture.group)
    #expect(fixture.order == [.tab(fixture.a), .tab(fixture.member), .tab(fixture.b), .tab(fixture.c)])
    try fixture.session.validate()
}

@Test func aGroupMovesToAnotherSpaceWithItsTabs() throws {
    var fixture = try PinnedFixture()
    let second = fixture.session.open(URL(string: "https://example.com/second")!, in: fixture.space)
    let member2 = try #require(second).id
    _ = fixture.session.move(id: member2, to: .list(group: fixture.group), before: nil)
    let work = try fixture.session.addSpace(name: "Work", profileID: fixture.session.profiles[0].id, color: .initial)
    let opened = fixture.session.open(URL(string: "https://example.com/work")!, in: work.id)
    let there = try #require(opened).id
    _ = fixture.session.move(id: there, to: .list(group: nil), before: nil)

    let transferred = fixture.session.transferGroup(id: fixture.group, to: work.id, before: there)
    let moved = try #require(transferred)
    #expect(moved == [fixture.member: fixture.member, member2: member2], "Within a profile, tabs keep their identity")
    #expect(fixture.session.pinned(in: work.id) == [.group(fixture.group), .tab(there)])
    #expect(fixture.session.tabs.filter { $0.place == .list(group: fixture.group) }.map(\.id) == [fixture.member, member2])
    #expect(fixture.order == [.tab(fixture.a), .tab(fixture.b), .tab(fixture.c)])
    try fixture.session.validate()

    let other = try fixture.session.addProfile(name: "Other")
    let elsewhere = try fixture.session.addSpace(name: "Elsewhere", profileID: other.id, color: .initial)
    let transferredAcross = fixture.session.transferGroup(id: fixture.group, to: elsewhere.id, before: nil)
    let crossed = try #require(transferredAcross)
    #expect(Set(crossed.keys) == [fixture.member, member2] && crossed.allSatisfy { $0.key != $0.value }, "Across profiles, new identities")
    try fixture.session.validate()
}

@Test func outOfRangeSlotsReadAsTheNearestValidOne() throws {
    let fixture = try PinnedFixture()
    var spaces = fixture.session.spaces
    spaces[0].groups = [TabGroup(id: fixture.group, name: "Reading", isCollapsed: false, slot: 99)]
    let decoded = BrowserSession(profiles: fixture.session.profiles, spaces: spaces, tabs: fixture.session.tabs)
    #expect(decoded.pinned(in: fixture.space).last == .group(fixture.group))
    spaces[0].groups[0].slot = -4
    #expect(BrowserSession(profiles: fixture.session.profiles, spaces: spaces, tabs: fixture.session.tabs).pinned(in: fixture.space).first == .group(fixture.group))
}

@Test func groupsMoveWithinTheirSpaceOnly() throws {
    var session = BrowserSession(profileName: "Personal")
    let main = try #require(session.spaces.first)
    try session.addSpace(name: "Work", profileID: main.profileID, color: .initial)
    let work = try #require(session.spaces.last)
    let added = ["A", "B", "C"].compactMap { session.addGroup(named: $0, in: main.id) }
    let other = session.addGroup(named: "Elsewhere", in: work.id)
    let elsewhere = try #require(other)
    try #require(added.count == 3)
    let a = added[0], c = added[2]
    func names() -> [String] { session.spaces[0].groups.map(\.name) }
    let first = session.moveGroup(id: c.id, before: a.id)
    #expect(first && names() == ["C", "A", "B"])
    let last = session.moveGroup(id: c.id, before: nil)
    #expect(last && names() == ["A", "B", "C"], "To the end")
    let refused = [session.moveGroup(id: a.id, before: elsewhere.id), session.moveGroup(id: a.id, before: a.id), session.moveGroup(id: UUID(), before: nil)]
    // Before another space's group, before itself, a group that does not exist.
    #expect(refused == [false, false, false])
    #expect(names() == ["A", "B", "C"] && session.spaces[1].groups.map(\.id) == [elsewhere.id])
    try session.validate()
}
