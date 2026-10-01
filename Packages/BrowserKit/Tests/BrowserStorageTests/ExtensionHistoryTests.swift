import BrowserCore
import Foundation
import Testing
@testable import BrowserStorage

// Failure modes: wrong profile, filtering visits instead of a page's last visit, losing older visits
// when deleting a bounded range, conflating visit IDs with page IDs, and sorting top sites by recency.
@Test func extensionHistoryKeepsVisitsCountsRangesAndProfiles() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "aero-extension-history-\(UUID())")
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = HistoryStore(file: folder.appending(path: "History.sqlite"))
    let profile = UUID(), other = UUID(), now = Date.now
    let popular = try #require(URL(string: "https://example.test/popular")), recent = try #require(URL(string: "https://example.test/recent"))
    try await store.recordVisit(to: popular, title: "Popular", profileID: profile, at: now - 30)
    try await store.recordVisit(to: popular, title: "Popular", profileID: profile, at: now - 20)
    try await store.recordVisit(to: popular, title: "Popular", profileID: profile, at: now - 10)
    try await store.recordVisit(to: recent, title: "Recent", profileID: profile, at: now)
    try await store.recordVisit(to: popular, title: "Other profile", profileID: other, at: now)
    let entries = try await store.search(profileID: profile, text: "", since: now - 60, until: now + 1, limit: 100)
    #expect(entries.map(\.url) == [recent, popular])
    #expect(entries.map(\.visitCount) == [1, 3])
    let visits = try await store.visits(to: popular, profileID: profile)
    #expect(visits.count == 3 && Set(visits.map(\.id)).count == 3)
    #expect(visits.allSatisfy { $0.pageID == entries[1].id })
    #expect(try await store.mostVisited(profileID: profile, limit: 2).map(\.url) == [popular, recent])
    try await store.deleteVisits(profileID: profile, from: now - 21, through: now - 9)
    let remaining = try await store.visits(to: popular, profileID: profile)
    #expect(remaining.count == 1 && remaining[0].date == now - 30)
    #expect(try await store.visits(to: popular, profileID: other).count == 1)
    #expect(try await store.search(profileID: profile, text: "Popular", since: now - 25, until: now + 1, limit: 100).isEmpty)
    try await store.delete(url: popular, profileID: profile)
    #expect(try await store.visits(to: popular, profileID: profile).isEmpty)
    #expect(try await store.visits(to: popular, profileID: other).count == 1)
}

// Failure modes: migration resets old visits, assigns invented provenance to imports,
// or a referring visit crosses profiles or dangles after its source is erased.
@Test func historyUpgradePreservesVisitsAndScopesTheirProvenance() async throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: "aero-history-upgrade-\(UUID())")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appending(path: "History.sqlite"), profile = UUID(), other = UUID(), now = Date.now
    let source = try #require(URL(string: "https://example.test/source")), target = try #require(URL(string: "https://example.test/target"))
    let baseline = try SQLiteDatabase(file: file)
    let schema = try #require(Bundle.module.url(forResource: "Fixtures/HistoryV1", withExtension: "sql"))
    try baseline.execute(String(contentsOf: schema, encoding: .utf8))
    try baseline.execute("PRAGMA application_id = 1095059529; PRAGMA user_version = 1")
    try baseline.run("INSERT INTO pages (id, profile_id, url, title, last_visit) VALUES (1, ?, ?, 'Existing', ?)",
                     [.text(profile.uuidString), .text(source.absoluteString), .real(now.timeIntervalSinceReferenceDate - 10)])
    try baseline.run("INSERT INTO visits (id, page_id, visited_at) VALUES (1, 1, ?)", [.real(now.timeIntervalSinceReferenceDate - 10)])
    let store = HistoryStore(file: file)
    let existing = try await store.visits(to: source, profileID: profile)
    #expect(existing.count == 1 && existing.first?.transition == .autoTopLevel && existing.first?.referringVisitID == nil)
    #expect(FileManager.default.fileExists(atPath: file.appendingPathExtension("upgrade-backup").path))
    try await store.recordVisit(to: source, title: nil, profileID: other, at: now - 5, transition: .typed)
    try await store.recordVisit(to: target, title: nil, profileID: profile, at: now, transition: .link, referrer: source)
    let visits = try await store.visits(to: target, profileID: profile)
    #expect(visits.first?.transition == .link && visits.first?.referringVisitID == existing.first?.id)
    #expect(try await store.delete(url: source, profileID: profile) == [source])
    #expect(try await store.visits(to: target, profileID: profile).first?.referringVisitID == nil)
    #expect(try await store.delete(url: source, profileID: profile).isEmpty)
    #expect(try await store.visits(to: source, profileID: other).count == 1)
}
