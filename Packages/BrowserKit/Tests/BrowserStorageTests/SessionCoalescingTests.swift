import BrowserCore
import BrowserStorage
import Foundation
import Testing

private let delay = Duration.milliseconds(50)

@Test func burstsOfChangesWriteOnlyTheLatestSnapshot() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = SessionStore(directory: folder, coalescingDelay: delay)
    var session = BrowserSession(profileName: "Personal")
    let first = session
    try session.addProfile(name: "Work", color: .ocean)
    let second = session
    try session.addProfile(name: "Studio", color: .plum)
    let latest = session

    async let firstSave: Void = store.scheduleSave(first, revision: 1)
    try await Task.sleep(for: delay / 5)
    #expect(try await store.load() == nil)
    try await store.scheduleSave(second, revision: 2)
    try await store.scheduleSave(latest, revision: 3)
    try await store.scheduleSave(first, revision: 1)
    try await firstSave
    #expect(try await store.load() == latest)
}

@Test func immediateSaveSupersedesAPendingWrite() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = SessionStore(directory: folder, coalescingDelay: delay)
    let pending = BrowserSession(profileName: "Personal")
    var flushed = pending
    try flushed.addProfile(name: "Work", color: .ocean)

    async let scheduled: Void = store.scheduleSave(pending, revision: 1)
    try await Task.sleep(for: delay / 5)
    try await store.save(flushed, revision: 2)
    try await scheduled
    #expect(try await store.load() == flushed)
}
