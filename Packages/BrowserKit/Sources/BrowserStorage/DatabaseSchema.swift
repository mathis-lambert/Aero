import Foundation

/// Append a migration; never edit one that has shipped. Array order defines schema versions.
struct DatabaseSchema {
    let identifier: Int64
    let migrations: [String]

    func prepare(_ database: SQLiteDatabase, file: URL) throws {
        let version = try database.query("PRAGMA user_version") { $0.integer(0) }.first ?? 0
        let identity = try database.query("PRAGMA application_id") { $0.integer(0) }.first ?? 0
        guard version >= 0 else { throw StorageError.invalidData }
        guard version <= migrations.count else { throw StorageError.newerVersion }
        if version == 0 {
            guard identity == 0,
                  try database.query("SELECT name FROM sqlite_schema WHERE name NOT LIKE 'sqlite_%'", row: { $0.text(0) }).isEmpty
            else { throw StorageError.foreignDatabase }
        } else {
            guard identity == identifier else { throw StorageError.foreignDatabase }
        }
        try database.checkIntegrity()
        if version > 0, version < migrations.count {
            try database.backup(to: file.appendingPathExtension("upgrade-backup"))
        }
        if version < migrations.count {
            // SQLite's table-rebuild procedure must not cascade a DROP into referencing rows.
            // Integrity is checked before commit; normal writes always enforce foreign keys.
            try database.execute("PRAGMA foreign_keys = OFF")
            do {
                try database.transaction {
                    for index in Int(version)..<migrations.count {
                        try database.execute(migrations[index])
                        try database.execute("PRAGMA user_version = \(index + 1)")
                    }
                    try database.execute("PRAGMA application_id = \(identifier)")
                    try database.checkIntegrity()
                }
            } catch {
                try database.execute("PRAGMA foreign_keys = ON")
                throw error
            }
        }
        try database.execute("PRAGMA foreign_keys = ON")
        try database.execute("PRAGMA journal_mode = WAL")
    }
}
