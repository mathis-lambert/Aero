import BrowserCore
@testable import BrowserStorage
import Foundation
import Testing

// Storage invariants in docs/STORAGE.md. SQL fault injection is unavailable through the UI.
private func location() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

@Test func relationalStateRoundTripAndStaleRevision() async throws {
    let folder = location()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = BrowserStore(directory: folder)
    #expect(try await store.load() == nil)
    var session = BrowserSession(profileName: "Personal")
    let work = try session.addProfile(name: "Work")
    let space = try session.addSpace(name: "Work", profileID: work.id, color: SpaceColor(0x0AB3FF), emoji: "🌊")
    let createdGroup = session.addGroup(named: "Research", in: space.id)
    let group = try #require(createdGroup)
    let opened = session.open(URL(string: "https://example.test/")!, in: space.id)
    let tab = try #require(opened)
    let moved = session.move(id: tab.id, to: .list(group: group.id), before: nil)
    #expect(moved)
    session.rename(id: tab.id, to: "Saved name")
    session.setDecision(.block, for: .camera, at: SiteOrigin(url: tab.url)!, profileID: work.id)
    var installed = InstalledExtension(id: String(repeating: "a", count: 32), version: "1", source: .webStore,
                                       grantedPermissions: ["storage"], grantedSites: ["https://example.test/*"])
    installed.isPinned = true
    session.setExtension(installed, profileID: work.id)
    session.setPasswordExtension(installed.id, profileID: work.id)
    session.setPasswordExtension("missing", profileID: work.id)
    #expect(session.profiles.first { $0.id == work.id }?.passwordExtension == installed.id, "Only an installed extension fills passwords")
    try await store.save(session, revision: 2)
    try await store.save(BrowserSession(profileName: "Stale"), revision: 1)
    await store.close()
    #expect(try await BrowserStore(directory: folder).load() == session)
}

// Failure modes: the upgrade loses profiles or extensions, invents a password extension, or a removed extension keeps
// filling passwords.
@Test func upgradeKeepsProfilesAndFillsPasswordsWithAeroUntilAnExtensionIsChosen() async throws {
    let folder = location()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("Browser.sqlite")
    let profile = UUID(), space = UUID(), extensionID = String(repeating: "b", count: 32)
    do {
        let baseline = try SQLiteDatabase(file: file)
        let schema = try #require(Bundle.module.url(forResource: "Fixtures/BrowserV1", withExtension: "sql"))
        try baseline.execute(String(contentsOf: schema, encoding: .utf8))
        try baseline.execute("PRAGMA application_id = \(0x41455232); PRAGMA user_version = 1; UPDATE state SET initialized = 1")
        try baseline.run("INSERT INTO profiles (id, name, removing, position) VALUES (?, 'Personal', 0, 0)", [.text(profile.uuidString)])
        try baseline.run("INSERT INTO spaces (id, profile_id, name, color, position) VALUES (?, ?, 'Main', '#0AB3FF', 0)",
                         [.text(space.uuidString), .text(profile.uuidString)])
        try baseline.run("INSERT INTO extensions (profile_id, id, version, package_id, enabled, pinned, removing, position) VALUES (?, ?, '1', ?, 1, 0, 0, 0)",
                         [.text(profile.uuidString), .text(extensionID), .text(UUID().uuidString)])
    }
    let store = BrowserStore(directory: folder)
    var session = try #require(try await store.load())
    #expect(session.profiles.map(\.id) == [profile])
    #expect(session.profiles[0].extensions.map(\.id) == [extensionID])
    #expect(session.profiles[0].passwordExtension == nil, "Aero fills passwords after the upgrade")
    session.setPasswordExtension(extensionID, profileID: profile)
    try await store.save(session, revision: 1)
    #expect(try await store.load()?.profiles[0].passwordExtension == extensionID)
    session.removeExtension(extensionID, profileID: profile)
    #expect(session.profiles[0].passwordExtension == nil, "A removed extension stops filling passwords")
    try await store.save(session, revision: 2)
    await store.close()
    #expect(try await BrowserStore(directory: folder).load()?.profiles[0].passwordExtension == nil)
}

@Test func failedStateTransactionIsRetryable() async throws {
    let folder = location()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = BrowserStore(directory: folder)
    _ = try await store.load()
    let original = BrowserSession(profileName: "Original")
    try await store.save(original, revision: 1)
    let database = try SQLiteDatabase(file: folder.appendingPathComponent("Browser.sqlite"))
    try database.execute("CREATE TRIGGER reject_tab BEFORE INSERT ON tabs BEGIN SELECT RAISE(ABORT, 'fixture'); END")
    var changed = original
    try changed.editProfile(id: original.profiles[0].id, name: "Changed")
    _ = changed.open(URL(string: "https://example.test")!, in: changed.spaces[0].id)
    await #expect(throws: (any Error).self) { try await store.save(changed, revision: 2) }
    #expect(try await store.load() == original)
    try database.execute("DROP TRIGGER reject_tab")
    try await store.save(changed, revision: 2)
    #expect(try await store.load() == changed)
}

@Test func secondWriterAndFutureSchemaAreRefused() async throws {
    let folder = location()
    defer { try? FileManager.default.removeItem(at: folder) }
    let first = BrowserStore(directory: folder)
    _ = try await first.load()
    let second = BrowserStore(directory: folder)
    await #expect(throws: StorageError.inUse) { try await second.load() }
    await first.close()
    let file = folder.appendingPathComponent("Browser.sqlite")
    do { let db = try SQLiteDatabase(file: file); try db.execute("PRAGMA user_version = 99") }
    let before = try Data(contentsOf: file)
    await #expect(throws: StorageError.newerVersion) { try await second.load() }
    #expect(try Data(contentsOf: file) == before)
}

@Test func migrationsRollbackAndAdvanceOnlyAfterSuccess() throws {
    let folder = location()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("fixture.sqlite")
    let db = try SQLiteDatabase(file: file)
    let first = DatabaseSchema(identifier: 12345, migrations: ["CREATE TABLE records (value TEXT NOT NULL);"])
    try first.prepare(db, file: file)
    try db.run("INSERT INTO records VALUES (?)", [.text("preserved")])
    let bad = DatabaseSchema(identifier: 12345, migrations: first.migrations + ["ALTER TABLE records ADD COLUMN note TEXT; INSERT INTO missing VALUES (1);"])
    #expect(throws: (any Error).self) { try bad.prepare(db, file: file) }
    #expect(try db.query("PRAGMA user_version") { $0.integer(0) } == [1])
    #expect(try db.query("PRAGMA table_info(records)") { $0.text(1) } == ["value"])
    let good = DatabaseSchema(identifier: 12345, migrations: first.migrations + ["ALTER TABLE records ADD COLUMN note TEXT NOT NULL DEFAULT 'kept';"])
    try good.prepare(db, file: file)
    #expect(try db.query("SELECT value || ':' || note FROM records") { $0.text(0) } == ["preserved:kept"])
    #expect(try db.query("PRAGMA user_version") { $0.integer(0) } == [2])
    try good.prepare(db, file: file)
    #expect(try db.query("SELECT count(*) FROM records") { $0.integer(0) } == [1])
}

@Test func corruptBrowserDatabaseIsPreserved() async throws {
    let folder = location()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("Browser.sqlite")
    let bytes = Data("broken database".utf8)
    try bytes.write(to: file)
    await #expect(throws: (any Error).self) { try await BrowserStore(directory: folder).load() }
    #expect(try Data(contentsOf: file) == bytes)
}

/// docs/STORAGE.md › Recovery: a missing database is never replaced by a fresh one while a snapshot shows data existed.
@Test func aMissingDatabaseWithASnapshotIsNotStartedFresh() async throws {
    let folder = location()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = BrowserStore(directory: folder)
    try await store.save(BrowserSession(profileName: "Saved"), revision: 1)
    #expect(try await store.createRecoverySnapshot() != nil)
    await store.close()
    try FileManager.default.removeItem(at: folder.appendingPathComponent("Browser.sqlite"))
    let reopened = BrowserStore(directory: folder)
    await #expect(throws: StorageError.invalidData) { try await reopened.load() }
    #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("Browser.sqlite").path), "Nothing fresh is created")
    #expect(await reopened.hasRecoverySnapshot())
}

/// docs/STORAGE.md › Recovery: restoring brings back the last good launch and archives the damaged file unchanged.
@Test func restoringTheSnapshotBringsBackTheLastGoodLaunch() async throws {
    let folder = location()
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = BrowserStore(directory: folder)
    var good = BrowserSession(profileName: "Good")
    _ = good.open(URL(string: "https://example.test/")!, in: good.spaces[0].id)
    try await store.save(good, revision: 1)
    _ = try await store.createRecoverySnapshot()
    var later = good
    try later.editProfile(id: good.profiles[0].id, name: "Later")
    try await store.save(later, revision: 2)
    await store.close()
    let damaged = Data("damaged records".utf8)
    try damaged.write(to: folder.appendingPathComponent("Browser.sqlite"))

    let reopened = BrowserStore(directory: folder)
    await #expect(throws: (any Error).self) { try await reopened.load() }
    try await reopened.restoreRecoverySnapshot()
    #expect(try await reopened.load() == good)
    let archives = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("Recovery-") }
    #expect(archives.count == 1)
    #expect(try Data(contentsOf: try #require(archives.first).appendingPathComponent("Browser.sqlite")) == damaged)
}

@Test func tableRebuildPreservesChildrenAndFailedMigrationRestoresForeignKeys() throws {
    let folder = location()
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = folder.appendingPathComponent("fixture.sqlite")
    let db = try SQLiteDatabase(file: file)
    let first = DatabaseSchema(identifier: 12345, migrations: ["""
        CREATE TABLE parent (id INTEGER PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE child (id INTEGER PRIMARY KEY, parent_id INTEGER REFERENCES parent(id) ON DELETE CASCADE);
        INSERT INTO parent VALUES (1, 'preserved');
        INSERT INTO child VALUES (2, 1);
        """])
    try first.prepare(db, file: file)
    let second = DatabaseSchema(identifier: 12345, migrations: first.migrations + ["""
        CREATE TABLE new_parent (id INTEGER PRIMARY KEY, value TEXT NOT NULL CHECK(length(value) > 0));
        INSERT INTO new_parent SELECT id, value FROM parent;
        DROP TABLE parent;
        ALTER TABLE new_parent RENAME TO parent;
        """])
    try second.prepare(db, file: file)
    #expect(try db.query("SELECT parent_id FROM child") { $0.integer(0) } == [1])
    let bad = DatabaseSchema(identifier: 12345, migrations: second.migrations + ["DELETE FROM parent;"])
    #expect(throws: StorageError.invalidData) { try bad.prepare(db, file: file) }
    #expect(try db.query("PRAGMA user_version") { $0.integer(0) } == [2])
    #expect(try db.query("PRAGMA foreign_keys") { $0.integer(0) } == [1])
    #expect(try db.query("SELECT parent_id FROM child") { $0.integer(0) } == [1])
}

// Failure modes: a group's place among loose favorites is lost on reload, or a group moved to another space is
// saved under its old one and the save fails.
@Test func groupsKeepTheirPlaceAndTheirSpaceAcrossSaves() async throws {
    let folder = location()
    defer { try? FileManager.default.removeItem(at: folder) }
    var session = BrowserSession(profileName: "Personal")
    let main = session.spaces[0]
    let work = try session.addSpace(name: "Work", profileID: main.profileID, color: .initial)
    let opened = [session.open(URL(string: "https://example.test/a")!, in: main.id), session.open(URL(string: "https://example.test/b")!, in: main.id)]
    let tabs = opened.compactMap(\.self)
    for tab in tabs { _ = session.move(id: tab.id, to: .list(group: nil), before: nil) }
    let added = session.addGroup(named: "Reading", in: main.id)
    let group = try #require(added)
    _ = session.moveGroup(id: group.id, before: tabs[1].id)
    let store = BrowserStore(directory: folder)
    try await store.save(session, revision: 1)
    #expect(try await store.load()?.pinned(in: main.id) == [.tab(tabs[0].id), .group(group.id), .tab(tabs[1].id)])

    _ = session.transferGroup(id: group.id, to: work.id, before: nil)
    try await store.save(session, revision: 2)
    await store.close()
    #expect(try await BrowserStore(directory: folder).load() == session)
}

// Failure modes: a split's layout or ratios read back different, or a split whose pane closed comes back.
@Test func splitsKeepTheirLayoutAcrossSaves() async throws {
    let folder = location()
    defer { try? FileManager.default.removeItem(at: folder) }
    var session = BrowserSession(profileName: "Personal")
    let space = session.spaces[0].id
    let tabs = (0..<3).compactMap { session.open(URL(string: "https://example.test/\($0)")!, in: space) }.map(\.id)
    session.split(tabs[1], beside: tabs[0], at: .trailing)
    session.split(tabs[2], beside: tabs[1], at: .bottom)
    let split = try #require(session.splits.first)
    session.resizeSplit(id: split.id, divider: SplitDivider.Place(path: [], index: 0), to: 0.35)
    let store = BrowserStore(directory: folder)
    try await store.save(session, revision: 1)
    #expect(try await store.load() == session)

    session.close(id: tabs[0])
    session.close(id: tabs[1])
    #expect(session.splits.isEmpty)
    try await store.save(session, revision: 2)
    await store.close()
    #expect(try await BrowserStore(directory: folder).load()?.splits.isEmpty == true)
}

@Test func aFavoriteKeepsItsPinnedPageAcrossSaves() async throws {
    let folder = location()
    defer { try? FileManager.default.removeItem(at: folder) }
    var session = BrowserSession(profileName: "Personal")
    let opened = session.open(URL(string: "https://example.test/home")!, in: session.spaces[0].id)
    let tab = try #require(opened)
    _ = session.move(id: tab.id, to: .grid, before: nil)
    session.updateTab(id: tab.id, url: URL(string: "https://example.test/elsewhere")!, title: "Elsewhere")
    let store = BrowserStore(directory: folder)
    try await store.save(session, revision: 1)
    await store.close()
    let loaded = try await BrowserStore(directory: folder).load()
    #expect(loaded?.tabs.first?.pinnedURL == URL(string: "https://example.test/home"))
    #expect(loaded?.tabs.first?.hasLeftPinnedPage == true)
}

@Test func aFolderKeepsItsIconAcrossSaves() async throws {
    let folder = location()
    defer { try? FileManager.default.removeItem(at: folder) }
    var session = BrowserSession(profileName: "Personal")
    let added = session.addGroup(named: "Work", in: session.spaces[0].id)
    let group = try #require(added)
    session.setGroupIcon(id: group.id, to: "briefcase")
    let store = BrowserStore(directory: folder)
    try await store.save(session, revision: 1)
    await store.close()
    #expect(try await BrowserStore(directory: folder).load()?.spaces[0].groups.first?.icon == "briefcase")
    session.setGroupIcon(id: group.id, to: " ")
    #expect(session.spaces[0].groups.first?.icon == nil, "A blank icon gives the folder back")
}
