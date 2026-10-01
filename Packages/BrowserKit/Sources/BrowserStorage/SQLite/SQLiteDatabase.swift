import Foundation
import SQLite3

/// Confined to its owning actor. Uses system SQLite; values are always bound.
final class SQLiteDatabase {
    enum Value { case integer(Int64), real(Double), text(String), null }
    struct Row {
        fileprivate let statement: OpaquePointer
        func isNull(_ column: Int32) -> Bool { sqlite3_column_type(statement, column) == SQLITE_NULL }
        func integer(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }
        func real(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }
        func text(_ column: Int32) -> String { optionalText(column) ?? "" }
        func optionalText(_ column: Int32) -> String? {
            guard let bytes = sqlite3_column_text(statement, column) else { return nil }
            let count = Int(sqlite3_column_bytes(statement, column))
            return String(decoding: UnsafeBufferPointer(start: bytes, count: count), as: UTF8.self)
        }
        func blob(_ column: Int32) -> Data {
            guard let bytes = sqlite3_column_blob(statement, column) else { return Data() }
            return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
        }
        func uuid(_ column: Int32) throws -> UUID {
            guard let value = UUID(uuidString: text(column)) else { throw StorageError.invalidData }
            return value
        }
    }

    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private let handle: OpaquePointer
    private var statements: [String: OpaquePointer] = [:]

    init(file: URL, readOnly: Bool = false) throws {
        var handle: OpaquePointer?
        let flags = (readOnly ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE) | SQLITE_OPEN_NOMUTEX
        let status = sqlite3_open_v2(file.path, &handle, flags, nil)
        guard status == SQLITE_OK, let handle else {
            sqlite3_close_v2(handle)
            throw StorageError.sqlite(status)
        }
        self.handle = handle
        sqlite3_extended_result_codes(handle, 1)
        // Bounded wait, off the main actor. A remaining BUSY is recoverable by the caller.
        sqlite3_busy_timeout(handle, 250)
    }

    deinit {
        statements.values.forEach { sqlite3_finalize($0) }
        sqlite3_close_v2(handle)
    }

    func execute(_ sql: String) throws {
        let status = sqlite3_exec(handle, sql, nil, nil, nil)
        guard status == SQLITE_OK else { throw StorageError.sqlite(status) }
    }

    func run(_ sql: String, _ values: [Value] = []) throws { _ = try query(sql, values) { _ in () } }

    func query<Result>(_ sql: String, _ values: [Value] = [], row: (Row) throws -> Result?) throws -> [Result] {
        let statement = try prepared(sql)
        defer { sqlite3_reset(statement); sqlite3_clear_bindings(statement) }
        guard sqlite3_bind_parameter_count(statement) == values.count else { throw StorageError.invalidData }
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            let status: Int32
            switch value {
            case .integer(let integer): status = sqlite3_bind_int64(statement, position, integer)
            case .real(let real): status = sqlite3_bind_double(statement, position, real)
            case .text(let text):
                status = text.withCString { sqlite3_bind_text(statement, position, $0, Int32(text.utf8.count), Self.transient) }
            case .null: status = sqlite3_bind_null(statement, position)
            }
            guard status == SQLITE_OK else { throw StorageError.sqlite(status) }
        }
        var results: [Result] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return results }
            guard status == SQLITE_ROW else { throw StorageError.sqlite(status) }
            if let result = try row(Row(statement: statement)) { results.append(result) }
        }
    }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try body(); try execute("COMMIT") }
        catch {
            // Preserve the original error; SQLite also rolls back on connection close.
            try? execute("ROLLBACK")
            throw error
        }
    }

    func checkIntegrity() throws {
        guard try query("PRAGMA quick_check", row: { $0.text(0) }) == ["ok"],
              try query("PRAGMA foreign_key_check", row: { $0.text(0) }).isEmpty else { throw StorageError.invalidData }
    }

    /// SQLite produces a consistent snapshot, including committed WAL pages.
    func backup(to file: URL) throws {
        let staged = file.deletingLastPathComponent().appendingPathComponent("backup-\(UUID().uuidString).sqlite")
        defer {
            // Only disposable staging files; an existing snapshot survives any failure.
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: staged.path + suffix))
            }
        }
        try writeBackup(to: staged)
        if FileManager.default.fileExists(atPath: file.path) {
            _ = try FileManager.default.replaceItemAt(file, withItemAt: staged)
        } else { try FileManager.default.moveItem(at: staged, to: file) }
    }

    private func writeBackup(to file: URL) throws {
        let destination = try SQLiteDatabase(file: file)
        guard let backup = sqlite3_backup_init(destination.handle, "main", handle, "main") else {
            throw StorageError.sqlite(sqlite3_errcode(destination.handle))
        }
        let status = sqlite3_backup_step(backup, -1)
        let finish = sqlite3_backup_finish(backup)
        guard status == SQLITE_DONE, finish == SQLITE_OK else { throw StorageError.sqlite(status == SQLITE_DONE ? finish : status) }
        // A portable snapshot must open read-only without WAL/SHM sidecars at its staging path.
        try destination.execute("PRAGMA journal_mode = DELETE")
        try destination.checkIntegrity()
    }

    private func prepared(_ sql: String) throws -> OpaquePointer {
        if let statement = statements[sql] { return statement }
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v3(handle, sql, -1, UInt32(SQLITE_PREPARE_PERSISTENT), &statement, nil)
        guard status == SQLITE_OK, let statement else { throw StorageError.sqlite(status) }
        statements[sql] = statement
        return statement
    }
}
