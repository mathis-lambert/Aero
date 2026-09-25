import BrowserStorage
import Foundation
import Testing

// Failure modes 5 and 7 in docs/BROWSING.md › Favicons.

private func makeFolder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
}

@Test func iconsAreIsolatedPerProfileAndHost() async throws {
    let folder = makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = FaviconStore(directory: folder)
    let personal = UUID()
    let work = UUID()
    let icon = Data([1, 2, 3])
    try await store.save(icon, host: "example.com", profileID: personal)
    #expect(await store.icon(host: "example.com", profileID: personal) == icon)
    #expect(await store.icon(host: "example.com", profileID: work) == nil)
    #expect(await store.icon(host: "example.org", profileID: personal) == nil)
}

@Test func hostileHostsStayInsideTheStore() async throws {
    let folder = makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = FaviconStore(directory: folder)
    let profile = UUID()
    try await store.save(Data([7]), host: "../../escape", profileID: profile)
    let escaped = folder.deletingLastPathComponent().appendingPathComponent("escape.png")
    #expect(!FileManager.default.fileExists(atPath: escaped.path))
    #expect(await store.icon(host: "../../escape", profileID: profile) == Data([7]))
}

@Test func oversizedIconsAreRefused() async throws {
    let folder = makeFolder()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = FaviconStore(directory: folder)
    let profile = UUID()
    let oversized = Data(count: FaviconStore.maximumIconBytes + 1)
    await #expect(throws: FaviconStore.Failure.iconTooLarge) {
        try await store.save(oversized, host: "example.com", profileID: profile)
    }
    #expect(await store.icon(host: "example.com", profileID: profile) == nil)
}
