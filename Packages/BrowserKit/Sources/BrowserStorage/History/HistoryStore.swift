import BrowserCore
import Foundation

/// Profile-scoped history in one SQLite database with a full-text index.
/// The database opens on first use; a file it cannot read is left untouched.
public actor HistoryStore {

    package static let retention: TimeInterval = 365 * 24 * 60 * 60
    package static let maximumTitleLength = 512
    package static let maximumURLLength = 2048
    public static let pageSize = 200
    private var database: SQLiteDatabase?
    private let file: URL
    private var nextMaintenance = Date.distantPast

    public init(file: URL) {
        self.file = file
    }

    public func recordVisit(to url: URL, title: String?, profileID: UUID, at date: Date = .now) throws {
        guard let address = Self.address(url) else { return }
        let database = try open()
        let page: [SQLiteDatabase.Value] = [.text(profileID.uuidString), .text(address)]
        try database.transaction {
            try database.run("""
                INSERT INTO pages (profile_id, url, title, last_visit) VALUES (?, ?, ?, ?)
                ON CONFLICT (profile_id, url) DO UPDATE SET
                    last_visit = max(last_visit, excluded.last_visit),
                    title = CASE WHEN excluded.title = '' THEN title ELSE excluded.title END
                """, page + [.text(Self.bounded(title)), .real(date.timeIntervalSinceReferenceDate)])
            try database.run("INSERT INTO visits (page_id, visited_at) SELECT id, ? FROM pages WHERE profile_id = ? AND url = ?",
                             [.real(date.timeIntervalSinceReferenceDate)] + page)
        }
    }

    /// Only updates existing entries, so a late title cannot bring back a cleared page.
    public func updateTitles(_ titles: [URL: String], profileID: UUID) throws {
        let database = try open()
        try database.transaction {
            for (url, title) in titles {
                guard let address = Self.address(url), !title.isEmpty else { continue }
                try database.run("UPDATE pages SET title = ? WHERE profile_id = ? AND url = ?",
                                 [.text(Self.bounded(title)), .text(profileID.uuidString), .text(address)])
            }
        }
    }

    /// Most recent first. `query` matches word prefixes in titles and addresses; FTS syntax in it
    /// is treated as text.
    public func entries(profileID: UUID, matching query: String = "", before: HistoryEntry.Cursor? = nil, limit: Int = pageSize) throws -> [HistoryEntry] {
        let database = try open()
        var bindings: [SQLiteDatabase.Value] = [.text(profileID.uuidString)]
        let columns = "pages.id, pages.url, pages.title, pages.last_visit"
        var source = "pages"
        var filter = "pages.profile_id = ?"
        if let before {
            filter += " AND (pages.last_visit, pages.id) < (?, ?)"
            bindings += [.real(before.date.timeIntervalSinceReferenceDate), .integer(before.id)]
        }
        if let match = Self.matchExpression(query) {
            source = "pages_fts JOIN pages ON pages.id = pages_fts.rowid"
            filter += " AND pages_fts MATCH ?"
            bindings.append(.text(match))
        }
        bindings.append(.integer(Int64(max(1, min(limit, 1000)))))
        return try database.query("SELECT \(columns) FROM \(source) WHERE \(filter) ORDER BY pages.last_visit DESC, pages.id DESC LIMIT ?",
                                  bindings, row: Self.entry)
    }

    public func delete(_ ids: [HistoryEntry.ID], profileID: UUID) throws {
        let database = try open()
        try database.transaction {
            for id in ids {
                try database.run("DELETE FROM pages WHERE id = ? AND profile_id = ?", [.integer(id), .text(profileID.uuidString)])
            }
        }
    }

    /// Removes visits since `date` (everything when `nil`); pages keep their older visits.
    public func clear(profileID: UUID, since date: Date?) throws {
        let database = try open()
        let profile = SQLiteDatabase.Value.text(profileID.uuidString)
        guard let date else {
            try database.run("DELETE FROM pages WHERE profile_id = ?", [profile])
            return
        }
        let since = SQLiteDatabase.Value.real(date.timeIntervalSinceReferenceDate)
        try database.transaction {
            try database.run("DELETE FROM visits WHERE visited_at >= ? AND page_id IN (SELECT id FROM pages WHERE profile_id = ?)",
                             [since, profile])
            try database.run("DELETE FROM pages WHERE profile_id = ? AND NOT EXISTS (SELECT 1 FROM visits WHERE page_id = pages.id)",
                             [profile])
            try database.run("""
                UPDATE pages SET last_visit = (SELECT max(visited_at) FROM visits WHERE page_id = pages.id)
                WHERE profile_id = ? AND last_visit >= ?
                """, [profile, since])
        }
    }

    /// Returns the space of deleted rows to the disk: SQLite otherwise keeps the file at its size.
    public func compact() throws {
        let database = try open()
        try database.run("PRAGMA wal_checkpoint(TRUNCATE)")
        try database.run("VACUUM")
    }

    // MARK: - Database

    private func open() throws -> SQLiteDatabase {
        let db: SQLiteDatabase
        if let database { db = database }
        else {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            db = try SQLiteDatabase(file: file)
            try Self.schema.prepare(db, file: file)
            try db.execute("PRAGMA synchronous = NORMAL")
            database = db
        }
        if Date.now >= nextMaintenance {
            // Maintenance is bounded and best effort. Contention must not disable reads.
            do {
                let cutoff = Date.now.addingTimeInterval(-Self.retention).timeIntervalSinceReferenceDate
                try db.transaction {
                    try db.run("DELETE FROM visits WHERE id IN (SELECT id FROM visits WHERE visited_at < ? LIMIT 500)", [.real(cutoff)])
                    try db.run("DELETE FROM pages WHERE id IN (SELECT id FROM pages WHERE last_visit < ? AND NOT EXISTS (SELECT 1 FROM visits WHERE page_id = pages.id) LIMIT 500)", [.real(cutoff)])
                }
                let more = try db.query("SELECT 1 FROM visits WHERE visited_at < ? LIMIT 1", [.real(cutoff)]) { $0.integer(0) }
                nextMaintenance = .now.addingTimeInterval(more.isEmpty ? 3600 : 60)
            } catch { nextMaintenance = .now.addingTimeInterval(60) }
        }
        return db
    }

    private static let schema = DatabaseSchema(identifier: 0x41454849, migrations: ["""
                CREATE TABLE pages (
                    id INTEGER PRIMARY KEY,
                    profile_id TEXT NOT NULL,
                    url TEXT NOT NULL,
                    title TEXT NOT NULL DEFAULT '',
                    last_visit REAL NOT NULL,
                    UNIQUE (profile_id, url)
                );
                CREATE INDEX pages_recent ON pages (profile_id, last_visit DESC, id DESC);
                CREATE TABLE visits (
                    id INTEGER PRIMARY KEY,
                    page_id INTEGER NOT NULL REFERENCES pages (id) ON DELETE CASCADE,
                    visited_at REAL NOT NULL
                );
                CREATE INDEX visits_page ON visits (page_id);
                CREATE INDEX visits_time ON visits (visited_at);
                CREATE VIRTUAL TABLE pages_fts USING fts5 (
                    title, url, content = 'pages', content_rowid = 'id', tokenize = 'unicode61 remove_diacritics 2'
                );
                CREATE TRIGGER pages_insert AFTER INSERT ON pages BEGIN
                    INSERT INTO pages_fts (rowid, title, url) VALUES (new.id, new.title, new.url);
                END;
                CREATE TRIGGER pages_delete AFTER DELETE ON pages BEGIN
                    INSERT INTO pages_fts (pages_fts, rowid, title, url) VALUES ('delete', old.id, old.title, old.url);
                END;
                CREATE TRIGGER pages_update AFTER UPDATE OF title, url ON pages BEGIN
                    INSERT INTO pages_fts (pages_fts, rowid, title, url) VALUES ('delete', old.id, old.title, old.url);
                    INSERT INTO pages_fts (rowid, title, url) VALUES (new.id, new.title, new.url);
                END;
                """])

    // MARK: - Values

    private static func address(_ url: URL) -> String? {
        let address = url.absoluteString
        return NavigationInput.isWebURL(url) && address.count <= maximumURLLength ? address : nil
    }

    private static func bounded(_ title: String?) -> String {
        String((title ?? "").prefix(maximumTitleLength))
    }

    /// Quotes each word as an FTS5 prefix phrase; words without letters or digits are dropped.
    private static func matchExpression(_ query: String) -> String? {
        let words = query.split(whereSeparator: \.isWhitespace)
            .filter { $0.unicodeScalars.contains(where: CharacterSet.alphanumerics.contains) }
            .map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*" }
        return words.isEmpty ? nil : words.joined(separator: " ")
    }

    private static func entry(_ row: SQLiteDatabase.Row) -> HistoryEntry? {
        guard let url = URL(string: row.text(1)) else { return nil }
        return HistoryEntry(id: row.integer(0), url: url, title: row.text(2),
                            lastVisit: Date(timeIntervalSinceReferenceDate: row.real(3)))
    }
}
