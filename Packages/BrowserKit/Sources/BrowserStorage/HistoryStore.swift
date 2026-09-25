import BrowserCore
import Foundation

/// Per-profile browsing history in a SQLite database with a full-text index.
/// The database opens on first use; a file it cannot read is left untouched.
public actor HistoryStore {
    public enum Failure: Error, Equatable { case unavailable }

    public static let retention: TimeInterval = 365 * 24 * 60 * 60
    public static let maximumTitleLength = 512
    public static let maximumURLLength = 2048
    public static let pageSize = 200
    private static let schemaVersion: Int64 = 1

    private enum State {
        case closed
        case open(SQLiteDatabase)
        case unavailable
    }

    private let file: URL
    private var state = State.closed

    public init(file: URL) {
        self.file = file
    }

    public func recordVisit(to url: URL, title: String?, profileID: UUID, at date: Date = .now) throws {
        guard let address = Self.address(url) else { return }
        let database = try open()
        let page: [SQLiteDatabase.Value] = [.text(profileID.uuidString), .text(address)]
        try database.transaction {
            try database.run("""
                INSERT INTO pages (profile_id, url, title, visit_count, last_visit) VALUES (?, ?, ?, 1, ?)
                ON CONFLICT (profile_id, url) DO UPDATE SET
                    visit_count = visit_count + 1,
                    last_visit = max(last_visit, excluded.last_visit),
                    title = CASE WHEN excluded.title = '' THEN title ELSE excluded.title END
                """, page + [.text(Self.bounded(title)), .real(date.timeIntervalSinceReferenceDate)])
            try database.run("INSERT INTO visits (page_id, visited_at) SELECT id, ? FROM pages WHERE profile_id = ? AND url = ?",
                             [.real(date.timeIntervalSinceReferenceDate)] + page)
        }
    }

    /// Only updates an existing entry, so a late title cannot bring back a cleared page.
    public func updateTitle(_ title: String, for url: URL, profileID: UUID) throws {
        guard let address = Self.address(url), !title.isEmpty else { return }
        try open().run("UPDATE pages SET title = ? WHERE profile_id = ? AND url = ?",
                       [.text(Self.bounded(title)), .text(profileID.uuidString), .text(address)])
    }

    /// Most recent first. `query` matches word prefixes in titles and addresses; FTS syntax in it
    /// is treated as text.
    public func entries(profileID: UUID, matching query: String = "", before: Date? = nil, limit: Int = pageSize) throws -> [HistoryEntry] {
        let database = try open()
        let before: SQLiteDatabase.Value = before.map { .real($0.timeIntervalSinceReferenceDate) } ?? .null
        let bindings: [SQLiteDatabase.Value] = [.text(profileID.uuidString), before, .integer(Int64(limit))]
        let columns = "pages.id, pages.url, pages.title, pages.last_visit, pages.visit_count"
        let filter = "pages.profile_id = ?1 AND (?2 IS NULL OR pages.last_visit < ?2)"
        if let match = Self.matchExpression(query) {
            return try database.query("""
                SELECT \(columns) FROM pages_fts JOIN pages ON pages.id = pages_fts.rowid
                WHERE pages_fts MATCH ?4 AND \(filter) ORDER BY pages.last_visit DESC LIMIT ?3
                """, bindings + [.text(match)], row: Self.entry)
        }
        return try database.query("SELECT \(columns) FROM pages WHERE \(filter) ORDER BY last_visit DESC LIMIT ?3",
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
                UPDATE pages SET
                    last_visit = (SELECT max(visited_at) FROM visits WHERE page_id = pages.id),
                    visit_count = (SELECT count(*) FROM visits WHERE page_id = pages.id)
                WHERE profile_id = ? AND last_visit >= ?
                """, [profile, since])
        }
    }

    // MARK: - Database

    private func open() throws -> SQLiteDatabase {
        switch state {
        case .open(let database): return database
        case .unavailable: throw Failure.unavailable
        case .closed:
            do {
                let database = try Self.prepare(file)
                state = .open(database)
                return database
            } catch {
                state = .unavailable
                throw Failure.unavailable
            }
        }
    }

    /// Reads the schema version before anything writes, so an unreadable or newer file is never modified.
    private static func prepare(_ file: URL) throws -> SQLiteDatabase {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let database = try SQLiteDatabase(file: file)
        let version = try database.query("PRAGMA user_version") { $0.integer(0) }.first ?? 0
        guard version <= schemaVersion else { throw Failure.unavailable }
        try database.execute("PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL; PRAGMA foreign_keys = ON")
        if version == 0 { try createSchema(database) }
        let cutoff = Date.now.addingTimeInterval(-retention).timeIntervalSinceReferenceDate
        try database.transaction {
            try database.run("DELETE FROM visits WHERE visited_at < ?", [.real(cutoff)])
            try database.run("DELETE FROM pages WHERE last_visit < ? AND NOT EXISTS (SELECT 1 FROM visits WHERE page_id = pages.id)",
                             [.real(cutoff)])
        }
        return database
    }

    private static func createSchema(_ database: SQLiteDatabase) throws {
        try database.transaction {
            try database.execute("""
                CREATE TABLE pages (
                    id INTEGER PRIMARY KEY,
                    profile_id TEXT NOT NULL,
                    url TEXT NOT NULL,
                    title TEXT NOT NULL DEFAULT '',
                    visit_count INTEGER NOT NULL DEFAULT 0,
                    last_visit REAL NOT NULL,
                    UNIQUE (profile_id, url)
                );
                CREATE INDEX pages_recent ON pages (profile_id, last_visit DESC);
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
                """)
            try database.execute("PRAGMA user_version = \(schemaVersion)")
        }
    }

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
                            lastVisit: Date(timeIntervalSinceReferenceDate: row.real(3)), visitCount: Int(row.integer(4)))
    }
}
