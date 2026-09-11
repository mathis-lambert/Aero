import BrowserCore
import BrowserStorage
import Foundation
import Testing

@Test func roundTripAndStaleWrites() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = SessionStore(directory: folder)
    #expect(try await store.load() == nil)
    let older = BrowserSession(profileName: "Personal")
    var newer = older
    try newer.addProfile(name: "Work", color: .ocean)
    try await store.save(newer, revision: 2)
    try await store.save(older, revision: 1)
    #expect(try await store.load() == newer)
}

@Test func unknownVersionsAndCorruptFilesArePreserved() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("session.json")
    let store = SessionStore(directory: folder)
    let future = Data(#"{"version":99}"#.utf8)
    try future.write(to: file)
    await #expect(throws: SessionStore.Failure.unsupportedVersion) { try await store.load() }
    #expect(try Data(contentsOf: file) == future)
    let corrupt = Data("broken".utf8)
    try corrupt.write(to: file)
    await #expect(throws: (any Error).self) { try await store.load() }
    #expect(try Data(contentsOf: file) == corrupt)
}
