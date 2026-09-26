import BrowserWebKit
import Foundation
import Testing

@Test @MainActor func storesAreReusedOnlyWithinTheSameProfile() {
    let registry = WebPageRegistry(downloads: makeTestDownloads(), extensionsFolder: FileManager.default.temporaryDirectory, ephemeral: true)
    let personal = UUID()
    let work = UUID()
    #expect(registry.dataStore(for: personal) === registry.dataStore(for: personal))
    #expect(registry.dataStore(for: personal) !== registry.dataStore(for: work))
    #expect(!registry.dataStore(for: personal).isPersistent)
}

@Test @MainActor func cookiesDoNotCrossProfileBoundaries() async throws {
    let registry = WebPageRegistry(downloads: makeTestDownloads(), extensionsFolder: FileManager.default.temporaryDirectory, ephemeral: true)
    let first = registry.dataStore(for: UUID())
    let second = registry.dataStore(for: UUID())
    let cookie = try #require(HTTPCookie(properties: [
        .domain: "example.com", .path: "/", .name: "profile-test", .value: "personal"
    ]))
    await first.httpCookieStore.setCookie(cookie)
    let firstCookies = await first.httpCookieStore.allCookies()
    let secondCookies = await second.httpCookieStore.allCookies()
    #expect(firstCookies.contains { $0.name == "profile-test" && $0.value == "personal" })
    #expect(!secondCookies.contains { $0.name == "profile-test" })
}
