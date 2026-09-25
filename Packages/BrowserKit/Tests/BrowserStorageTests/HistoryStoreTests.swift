import BrowserCore
import BrowserStorage
import Foundation
import SQLite3
import Testing

// Failure modes 1–7 and 9 in docs/HISTORY.md.

private let day: TimeInterval = 24 * 60 * 60

private struct Fixture {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    var file: URL { folder.appendingPathComponent("History.sqlite") }
    func store() -> HistoryStore { HistoryStore(file: file) }
    func remove() { try? FileManager.default.removeItem(at: folder) }
}

private func url(_ string: String) throws -> URL { try #require(URL(string: string)) }

@Test func searchTreatsQuerySyntaxAsTextAndIgnoresDiacritics() async throws {
    let fixture = Fixture()
    defer { fixture.remove() }
    let store = fixture.store()
    let profile = UUID()
    try await store.recordVisit(to: url("https://example.com/cpp"), title: #"C++ and "quotes" NEAR (OR)"#, profileID: profile)
    try await store.recordVisit(to: url("https://lyon.example/ete"), title: "Été à Lyon", profileID: profile)
    for query in [#"""#, "*", "-", "NEAR", "OR (", "c++ \"", "AND NOT"] {
        _ = try await store.entries(profileID: profile, matching: query)
    }
    #expect(try await store.entries(profileID: profile, matching: "quot").map(\.title) == [#"C++ and "quotes" NEAR (OR)"#])
    #expect(try await store.entries(profileID: profile, matching: "ete lyo").map(\.title) == ["Été à Lyon"])
    #expect(try await store.entries(profileID: profile, matching: "example.com").count == 1)
}

@Test func profilesAreIsolated() async throws {
    let fixture = Fixture()
    defer { fixture.remove() }
    let store = fixture.store()
    let personal = UUID()
    let work = UUID()
    let page = try url("https://example.com")
    try await store.recordVisit(to: page, title: "Personal title", profileID: personal)
    try await store.recordVisit(to: page, title: "Work title", profileID: work)
    #expect(try await store.entries(profileID: personal).map(\.title) == ["Personal title"])
    try await store.clear(profileID: personal, since: nil)
    #expect(try await store.entries(profileID: personal).isEmpty)
    #expect(try await store.entries(profileID: work).map(\.title) == ["Work title"])
}

@Test func clearingARangeKeepsOlderVisits() async throws {
    let fixture = Fixture()
    defer { fixture.remove() }
    let store = fixture.store()
    let profile = UUID()
    let now = Date.now
    let revisited = try url("https://example.com/revisited")
    try await store.recordVisit(to: revisited, title: "Revisited", profileID: profile, at: now - 3 * day)
    try await store.recordVisit(to: revisited, title: "Revisited", profileID: profile, at: now)
    try await store.recordVisit(to: url("https://example.com/new"), title: "New", profileID: profile, at: now)
    try await store.clear(profileID: profile, since: now - day / 24)
    let remaining = try await store.entries(profileID: profile)
    #expect(remaining.map(\.title) == ["Revisited"])
    #expect(abs(try #require(remaining.first).lastVisit.timeIntervalSince(now - 3 * day)) < 1)
}

@Test func deletingEntriesIsScopedToTheProfile() async throws {
    let fixture = Fixture()
    defer { fixture.remove() }
    let store = fixture.store()
    let personal = UUID()
    try await store.recordVisit(to: url("https://example.com"), title: "Example", profileID: personal)
    let entry = try #require(try await store.entries(profileID: personal).first)
    try await store.delete([entry.id], profileID: UUID())
    #expect(try await store.entries(profileID: personal).count == 1)
    try await store.delete([entry.id], profileID: personal)
    #expect(try await store.entries(profileID: personal).isEmpty)
}

@Test func unreadableAndFutureDatabasesArePreserved() async throws {
    let fixture = Fixture()
    defer { fixture.remove() }
    try FileManager.default.createDirectory(at: fixture.folder, withIntermediateDirectories: true)
    let garbage = Data("not a database".utf8)
    try garbage.write(to: fixture.file)
    await #expect(throws: HistoryStore.Failure.unavailable) {
        try await fixture.store().recordVisit(to: url("https://example.com"), title: nil, profileID: UUID())
    }
    #expect(try Data(contentsOf: fixture.file) == garbage)

    try FileManager.default.removeItem(at: fixture.file)
    var database: OpaquePointer?
    #expect(sqlite3_open(fixture.file.path, &database) == SQLITE_OK)
    #expect(sqlite3_exec(database, "PRAGMA user_version = 99", nil, nil, nil) == SQLITE_OK)
    sqlite3_close(database)
    let future = try Data(contentsOf: fixture.file)
    await #expect(throws: HistoryStore.Failure.unavailable) { try await fixture.store().entries(profileID: UUID()) }
    #expect(try Data(contentsOf: fixture.file) == future)
}

@Test func reopeningKeepsDataAndPrunesVisitsOlderThanTheRetention() async throws {
    let fixture = Fixture()
    defer { fixture.remove() }
    let profile = UUID()
    let now = Date.now
    let first = fixture.store()
    try await first.recordVisit(to: url("https://example.com/kept"), title: "Kept", profileID: profile, at: now)
    try await first.recordVisit(to: url("https://example.com/old"), title: "Old", profileID: profile,
                                at: now - HistoryStore.retention - day)
    #expect(try await fixture.store().entries(profileID: profile).map(\.title) == ["Kept"])
}

@Test func oversizedValuesAreBounded() async throws {
    let fixture = Fixture()
    defer { fixture.remove() }
    let store = fixture.store()
    let profile = UUID()
    try await store.recordVisit(to: url("https://example.com"), title: String(repeating: "t", count: 10_000), profileID: profile)
    let long = try url("https://example.com/" + String(repeating: "p", count: HistoryStore.maximumURLLength))
    try await store.recordVisit(to: long, title: "Too long", profileID: profile)
    let entries = try await store.entries(profileID: profile)
    #expect(entries.count == 1)
    #expect(try #require(entries.first).title.count == HistoryStore.maximumTitleLength)
}

@Test func lateTitlesDoNotResurrectClearedEntries() async throws {
    let fixture = Fixture()
    defer { fixture.remove() }
    let store = fixture.store()
    let profile = UUID()
    let page = try url("https://example.com")
    try await store.recordVisit(to: page, title: nil, profileID: profile)
    try await store.clear(profileID: profile, since: nil)
    try await store.updateTitle("Late", for: page, profileID: profile)
    #expect(try await store.entries(profileID: profile).isEmpty)
}
