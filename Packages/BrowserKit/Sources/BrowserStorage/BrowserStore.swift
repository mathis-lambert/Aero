import BrowserCore
import Foundation
import os

/// Authoritative browser records. Transactions update changed rows; WebKit and history remain separate.
public actor BrowserStore {
    private let directory: URL
    private var file: URL { directory.appendingPathComponent("Browser.sqlite") }
    private var recovery: URL { directory.appendingPathComponent("Browser.recovery.sqlite") }
    private var recoveryPending: URL { directory.appendingPathComponent("Recovery.pending") }
    private var lock: StorageLock?
    private var database: SQLiteDatabase?
    private var committed: BrowserSession?
    private var revision: UInt64 = 0
    private var loaded = false
    private static let signposter = OSSignposter(subsystem: Diagnostics.subsystem, category: Diagnostics.Category.storage)

    public init(directory: URL) { self.directory = directory }

    public func load() throws -> BrowserSession? {
        let interval = Self.signposter.beginInterval(Diagnostics.Signpost.sessionLoad)
        defer { Self.signposter.endInterval(Diagnostics.Signpost.sessionLoad, interval) }
        do {
            let db = try open()
            let session = try Self.read(db)
            committed = session
            loaded = true
            return session
        } catch {
            database = nil
            committed = nil
            loaded = false
            throw error
        }
    }

    public func save(_ session: BrowserSession, revision: UInt64) throws {
        guard revision >= self.revision else { return }
        if !loaded { _ = try load() }
        try session.validate()
        let db = try open()
        let interval = Self.signposter.beginInterval(Diagnostics.Signpost.sessionWrite)
        defer { Self.signposter.endInterval(Diagnostics.Signpost.sessionWrite, interval) }
        if committed != session {
            try db.transaction {
                try Self.write(session, previous: committed, to: db)
                try db.execute("UPDATE state SET initialized = 1 WHERE id = 1")
            }
            committed = session
        }
        self.revision = revision
    }

    /// One known-good launch generation, before this launch mutates records. Never called on failed load.
    /// Returns the packages retained by this snapshot; nil withholds cleanup for older upgrade backups.
    public func createRecoverySnapshot() throws -> Set<UUID>? {
        guard loaded, let committed else { return nil }
        try open().backup(to: recovery)
        guard !FileManager.default.fileExists(atPath: file.appendingPathExtension("upgrade-backup").path) else { return nil }
        return Set(committed.profiles.flatMap(\.extensions).map(\.packageID))
    }

    public func hasRecoverySnapshot() -> Bool {
        guard let db = try? SQLiteDatabase(file: recovery, readOnly: true) else { return false }
        return (try? Self.readRecovery(db)) != nil
    }

    /// Explicit recovery preserves the damaged files. Never used automatically or for a newer schema.
    public func restoreRecoverySnapshot() throws {
        guard lock != nil else { throw StorageError.inUse }
        let backup = try SQLiteDatabase(file: recovery, readOnly: true)
        _ = try Self.readRecovery(backup)
        let staged = directory.appendingPathComponent("restore-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: staged) }
        try backup.backup(to: staged)
        database = nil
        let archive = directory.appendingPathComponent("Recovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: false)
        // A crash at any later step keeps startup blocked until explicit recovery completes.
        try Data(archive.lastPathComponent.utf8).write(to: recoveryPending, options: .atomic)
        for suffix in ["", "-wal", "-shm"] {
            let source = URL(fileURLWithPath: file.path + suffix)
            if FileManager.default.fileExists(atPath: source.path) {
                try FileManager.default.copyItem(at: source, to: archive.appendingPathComponent(source.lastPathComponent))
            }
        }
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: file.path + suffix)
            if FileManager.default.fileExists(atPath: sidecar.path) { try FileManager.default.removeItem(at: sidecar) }
        }
        if FileManager.default.fileExists(atPath: file.path) {
            _ = try FileManager.default.replaceItemAt(file, withItemAt: staged)
        } else { try FileManager.default.moveItem(at: staged, to: file) }
        try FileManager.default.removeItem(at: recoveryPending)
        committed = nil; revision = 0; loaded = false
    }

    func close() { database = nil; lock = nil; committed = nil; loaded = false; revision = 0 }

    private func open() throws -> SQLiteDatabase {
        if let database { return database }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        if lock == nil { lock = try StorageLock(directory: directory) }
        guard !FileManager.default.fileExists(atPath: recoveryPending.path) else { throw StorageError.invalidData }
        if !FileManager.default.fileExists(atPath: file.path) {
            let evidence = [recovery, file.appendingPathExtension("upgrade-backup"), URL(fileURLWithPath: file.path + "-wal")]
            guard !evidence.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) else { throw StorageError.invalidData }
        }
        let db = try SQLiteDatabase(file: file)
        try DatabaseSchema.browser.prepare(db, file: file)
        try db.execute("PRAGMA synchronous = FULL")
        database = db
        return db
    }

    private static func readRecovery(_ db: SQLiteDatabase) throws -> BrowserSession {
        guard try db.query("PRAGMA application_id", row: { $0.integer(0) }) == [DatabaseSchema.browser.identifier],
              try db.query("PRAGMA user_version", row: { $0.integer(0) }) == [Int64(DatabaseSchema.browser.migrations.count)]
        else { throw StorageError.invalidData }
        try db.checkIntegrity()
        guard let session = try read(db) else { throw StorageError.invalidData }
        return session
    }

    private static func read(_ db: SQLiteDatabase) throws -> BrowserSession? {
        let initialized = try db.query("SELECT initialized FROM state WHERE id = 1") { $0.integer(0) }
        guard initialized == [0] || initialized == [1] else { throw StorageError.invalidData }
        var profiles = try db.query("SELECT id, name, color, emoji FROM profiles ORDER BY position") { row -> BrowserProfile in
            guard let color = ProfileColor(rawValue: row.text(2)) else { throw StorageError.invalidData }
            return try BrowserProfile(id: row.uuid(0), name: row.text(1), color: color, emoji: row.optionalText(3))
        }
        if initialized == [0] {
            guard profiles.isEmpty else { throw StorageError.invalidData }
            return nil
        }
        for index in profiles.indices {
            let id = profiles[index].id
            let permissions = try db.query("SELECT origin, permission, decision FROM site_permissions WHERE profile_id = ?", [.text(id.uuidString)]) { row -> (SiteOrigin, SitePermission, SiteDecision) in
                guard let origin = SiteOrigin(rawValue: row.text(0)), let permission = SitePermission(rawValue: row.text(1)),
                      let decision = SiteDecision(rawValue: row.text(2)) else { throw StorageError.invalidData }
                return (origin, permission, decision)
            }
            for (origin, permission, decision) in permissions { profiles[index].sitePermissions[origin, default: [:]][permission] = decision }
            profiles[index].extensions = try db.query("SELECT id, version, package_id, source_folder, enabled, pinned, removing, pending_version FROM extensions WHERE profile_id = ? ORDER BY position", [.text(id.uuidString)]) { row -> InstalledExtension in
                let source: InstalledExtension.Source
                if let path = row.optionalText(3) {
                    guard let url = URL(string: path), url.isFileURL else { throw StorageError.invalidData }
                    source = .folder(url)
                } else { source = .webStore }
                let grants = try db.query("SELECT kind, value FROM extension_grants WHERE profile_id = ? AND extension_id = ? ORDER BY value", [.text(id.uuidString), .text(row.text(0))]) { ($0.text(0), $0.text(1)) }
                var record = InstalledExtension(id: row.text(0), version: row.text(1), source: source,
                    grantedPermissions: grants.filter { $0.0 == "permission" }.map(\.1), grantedSites: grants.filter { $0.0 == "site" }.map(\.1))
                record.packageID = try row.uuid(2)
                record.isEnabled = row.integer(4) != 0; record.isPinned = row.integer(5) != 0
                record.isRemoving = row.integer(6) != 0; record.pendingVersion = row.optionalText(7)
                return record
            }
        }
        var spaces = try db.query("SELECT id, profile_id FROM spaces ORDER BY position") { try BrowserSpace(id: $0.uuid(0), profileID: $0.uuid(1)) }
        for index in spaces.indices {
            spaces[index].groups = try db.query("SELECT id, name, collapsed FROM tab_groups WHERE space_id = ? ORDER BY position", [.text(spaces[index].id.uuidString)]) {
                try TabGroup(id: $0.uuid(0), name: $0.text(1), isCollapsed: $0.integer(2) != 0)
            }
        }
        let tabs = try db.query("SELECT id, space_id, url, title, custom_name, placement, group_id FROM tabs ORDER BY position") { row -> BrowserTab in
            guard let url = URL(string: row.text(2)) else { throw StorageError.invalidData }
            let place: TabPlace
            switch row.text(5) {
            case "open": place = .open
            case "grid": place = .grid
            case "list": place = .list(group: row.optionalText(6) == nil ? nil : try row.uuid(6))
            default: throw StorageError.invalidData
            }
            return try BrowserTab(id: row.uuid(0), spaceID: row.uuid(1), url: url, title: row.text(3), name: row.optionalText(4), place: place)
        }
        let session = BrowserSession(profiles: profiles, spaces: spaces, tabs: tabs)
        try session.validate()
        return session
    }

    private static func write(_ session: BrowserSession, previous: BrowserSession?, to db: SQLiteDatabase) throws {
        let tabIDs = Set(session.tabs.map(\.id))
        let groupIDs = Set(session.spaces.flatMap(\.groups).map(\.id))
        let spaceIDs = Set(session.spaces.map(\.id))
        let profileIDs = Set(session.profiles.map(\.id))
        let oldProfiles = Dictionary(uniqueKeysWithValues: (previous?.profiles ?? []).map { ($0.id, $0) })
        for old in previous?.tabs ?? [] where !tabIDs.contains(old.id) {
            try db.run("DELETE FROM tabs WHERE id = ?", [.text(old.id.uuidString)])
        }
        for old in previous?.spaces.flatMap(\.groups) ?? [] where !groupIDs.contains(old.id) {
            try db.run("DELETE FROM tab_groups WHERE id = ?", [.text(old.id.uuidString)])
        }
        for old in previous?.spaces ?? [] where !spaceIDs.contains(old.id) {
            try db.run("DELETE FROM spaces WHERE id = ?", [.text(old.id.uuidString)])
        }
        for old in previous?.profiles ?? [] where !profileIDs.contains(old.id) {
            try db.run("DELETE FROM profiles WHERE id = ?", [.text(old.id.uuidString)])
        }
        for (position, profile) in session.profiles.enumerated() {
            let old = oldProfiles[profile.id]
            let id = SQLiteDatabase.Value.text(profile.id.uuidString)
            if old != profile || previous?.profiles.indices.contains(position) != true || previous?.profiles[position].id != profile.id {
                try db.run("INSERT INTO profiles (id,name,color,emoji,position) VALUES (?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,color=excluded.color,emoji=excluded.emoji,position=excluded.position",
                           [id, .text(profile.name), .text(profile.color.rawValue), text(profile.emoji), .integer(Int64(position))])
            }
            if old?.sitePermissions != profile.sitePermissions {
                try db.run("DELETE FROM site_permissions WHERE profile_id = ?", [id])
                for (origin, decisions) in profile.sitePermissions {
                    for (permission, decision) in decisions {
                        try db.run("INSERT INTO site_permissions (profile_id,origin,permission,decision) VALUES (?, ?, ?, ?)", [id, .text(origin.rawValue), .text(permission.rawValue), .text(decision.rawValue)])
                    }
                }
            }
            if old?.extensions != profile.extensions {
                try db.run("DELETE FROM extensions WHERE profile_id = ?", [id])
                for (index, record) in profile.extensions.enumerated() {
                    let source: String? = if case .folder(let url) = record.source { url.absoluteString } else { nil }
                    try db.run("INSERT INTO extensions (profile_id,id,version,package_id,source_folder,enabled,pinned,removing,pending_version,position) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", [id, .text(record.id), .text(record.version), .text(record.packageID.uuidString), text(source), .integer(record.isEnabled ? 1 : 0), .integer(record.isPinned ? 1 : 0), .integer(record.isRemoving ? 1 : 0), text(record.pendingVersion), .integer(Int64(index))])
                    for (kind, values) in [("permission", record.grantedPermissions), ("site", record.grantedSites)] {
                        for value in values { try db.run("INSERT INTO extension_grants (profile_id,extension_id,kind,value) VALUES (?, ?, ?, ?)", [id, .text(record.id), .text(kind), .text(value)]) }
                    }
                }
            }
        }
        let oldSpaces = Dictionary(uniqueKeysWithValues: (previous?.spaces ?? []).map { ($0.id, $0) })
        for (position, space) in session.spaces.enumerated() {
            if oldSpaces[space.id] != space || previous?.spaces.indices.contains(position) != true || previous?.spaces[position].id != space.id {
                try db.run("INSERT INTO spaces (id,profile_id,position) VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET position=excluded.position", [.text(space.id.uuidString), .text(space.profileID.uuidString), .integer(Int64(position))])
                for (index, group) in space.groups.enumerated() {
                    try db.run("INSERT INTO tab_groups (id,space_id,name,collapsed,position) VALUES (?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET name=excluded.name,collapsed=excluded.collapsed,position=excluded.position",
                               [.text(group.id.uuidString), .text(space.id.uuidString), .text(group.name), .integer(group.isCollapsed ? 1 : 0), .integer(Int64(index))])
                }
            }
        }
        let oldTabs = Dictionary(uniqueKeysWithValues: (previous?.tabs ?? []).enumerated().map { ($0.element.id, ($0.offset, $0.element)) })
        for (position, tab) in session.tabs.enumerated() {
            guard oldTabs[tab.id]?.0 != position || oldTabs[tab.id]?.1 != tab else { continue }
            let place: String
            let group: String?
            switch tab.place {
            case .open: place = "open"; group = nil
            case .grid: place = "grid"; group = nil
            case .list(let id): place = "list"; group = id?.uuidString
            }
            try db.run("INSERT INTO tabs (id,space_id,url,title,custom_name,placement,group_id,position) VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET space_id=excluded.space_id,url=excluded.url,title=excluded.title,custom_name=excluded.custom_name,placement=excluded.placement,group_id=excluded.group_id,position=excluded.position",
                       [.text(tab.id.uuidString), .text(tab.spaceID.uuidString), .text(tab.url.absoluteString), .text(tab.title), text(tab.name), .text(place), text(group), .integer(Int64(position))])
        }
    }

    private static func text(_ value: String?) -> SQLiteDatabase.Value { value.map(SQLiteDatabase.Value.text) ?? .null }
}
