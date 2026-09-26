import Foundation
import Testing
@testable import BrowserCore

@Test func profilesHaveIndependentSpaces() throws {
    var session = BrowserSession(profileName: "Personal")
    let originalSpace = try #require(session.spaces.first)
    let work = try session.addProfile(name: "  Work  ", color: .ocean)
    let workSpace = try #require(session.spaces.first { $0.profileID == work.id })
    #expect(work.name == "Work")
    let url = try #require(URL(string: "https://example.com"))
    let firstResult = session.open(url, in: originalSpace.id)
    let firstTab = try #require(firstResult)
    let workResult = session.open(url, in: workSpace.id)
    let workTab = try #require(workResult)
    #expect(firstTab.spaceID != workTab.spaceID)
    #expect(session.tabs.count == 2)
    try session.validate()
}

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

@Test func profileNamesCannotBeBlank() throws {
    var session = BrowserSession(profileName: "Personal")
    #expect(throws: SessionError.invalidProfileName) { try session.addProfile(name: " \n ", color: .moss) }
    #expect(throws: SessionError.invalidProfileName) {
        try session.addProfile(name: String(repeating: "a", count: BrowserProfile.maximumNameLength + 1), color: .moss)
    }
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
