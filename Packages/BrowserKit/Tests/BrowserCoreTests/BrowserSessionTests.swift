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

// Failure modes 5 and 6 in docs/PROFILES.md.
@Test func profileEmojiIsExactlyOneEmoji() {
    for emoji in ["🚀", "❤️", "🇫🇷", "👩‍👩‍👧", "👍🏽", "1️⃣", " 🌿 "] {
        #expect(BrowserProfile.emoji(from: emoji) == emoji.trimmingCharacters(in: .whitespaces), "\(emoji)")
    }
    for text in ["", " ", "a", "Work", "1", "#", "🚀🌿", "🚀a", "\u{1F3FD}", "\u{FE0F}", "❤"] {
        #expect(BrowserProfile.emoji(from: text) == nil, "\(text)")
    }
}

@Test func sessionsValidateProfileEmoji() throws {
    var session = BrowserSession(profileName: "Personal")
    let work = try session.addProfile(name: "Work", color: .ocean, emoji: "🚀")
    #expect(work.emoji == "🚀")
    try session.validate()
    try session.editProfile(id: work.id, name: "Work", color: .ocean, emoji: nil)
    #expect(session.profiles.last?.emoji == nil)
    #expect(throws: SessionError.invalidEmoji) { try session.editProfile(id: work.id, name: "Work", color: .ocean, emoji: "Work") }

    let data = try JSONEncoder().encode(session)
    let tampered = try #require(String(data: data, encoding: .utf8)?.replacingOccurrences(of: "\"name\":\"Work\"", with: "\"name\":\"Work\",\"emoji\":\"ab\""))
    let decoded = try JSONDecoder().decode(BrowserSession.self, from: Data(tampered.utf8))
    #expect(throws: SessionError.inconsistentData) { try decoded.validate() }
}

// Failure modes 4 and 5 in docs/BROWSING.md › Favorites and open tabs.
@Test func tabsStayInTheirSpaceAndItsGroups() throws {
    var session = BrowserSession(profileName: "Personal")
    let personal = try #require(session.spaces.first)
    try session.addProfile(name: "Work", color: .ocean)
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

    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    let saved = try #require(String(data: try encoder.encode(session), encoding: .utf8))
    // Spaces sort before tabs, so the first mention is the group's own record.
    let range = try #require(saved.range(of: group.id.uuidString))
    let tampered = saved.replacingCharacters(in: range, with: UUID().uuidString)
    let decoded = try JSONDecoder().decode(BrowserSession.self, from: Data(tampered.utf8))
    #expect(throws: SessionError.inconsistentData) { try decoded.validate() }

    session.removeGroup(id: group.id)
    #expect(session.tabs.first { $0.id == theirs.id }?.place == .list(group: nil), "Ungrouping keeps the favorite")
    try session.validate()
}
