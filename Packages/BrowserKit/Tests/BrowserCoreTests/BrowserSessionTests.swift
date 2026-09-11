import Foundation
import Testing
@testable import BrowserCore

@Test func profilesHaveIndependentSpaces() throws {
    var session = BrowserSession(profileName: "Personal")
    let originalSpace = try #require(session.spaces.first)
    let work = try session.addProfile(name: "  Work  ", color: .ocean)
    let workSpace = try #require(session.spaces.first { $0.profileID == work.id })
    #expect(work.name == "Work")
    let url = try NavigationInput.resolve("example.com")
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
    let url = try NavigationInput.resolve("example.com")
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

@Test func resolvesAddressesAndInternationalSearch() throws {
    #expect(try NavigationInput.resolve("example.com/a").absoluteString == "https://example.com/a")
    #expect(try NavigationInput.resolve("localhost:8080").absoluteString == "http://localhost:8080")
    let url = try NavigationInput.resolve("été à Lyon")
    #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "été à Lyon")
    #expect(throws: NavigationInput.Failure.self) { try NavigationInput.resolve("javascript:alert(1)") }
    #expect(throws: NavigationInput.Failure.self) { try NavigationInput.resolve("file:///etc/passwd") }
}
