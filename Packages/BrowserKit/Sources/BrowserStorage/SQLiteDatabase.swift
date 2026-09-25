import Foundation
import SQLite3

/// A minimal wrapper over the system SQLite library. Not thread-safe: each instance is confined
/// to the actor that owns it. Every value is bound, never interpolated into SQL.
final class SQLiteDatabase {
    enum Failure: Error { case open(Int32), statement(Int32) }

    enum Value {
        case integer(Int64), real(Double), text(String), null
    }

    struct Row {
        fileprivate let statement: OpaquePointer
        func integer(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }
        func real(_ column: Int32) -> Double { sqlite3_column_double(statement, column) }
        func text(_ column: Int32) -> String { sqlite3_column_text(statement, column).map { String(cString: $0) } ?? "" }
    }

    /// SQLite copies bound text before the call returns.
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private let handle: OpaquePointer
    private var statements: [String: OpaquePointer] = [:]

    /// Opening does not read or write the file; the first statement does.
    init(file: URL) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX
        let status = sqlite3_open_v2(file.path, &handle, flags, nil)
        guard status == SQLITE_OK, let handle else {
            sqlite3_close_v2(handle)
            throw Failure.open(status)
        }
        self.handle = handle
    }

    deinit {
        statements.values.forEach { sqlite3_finalize($0) }
        sqlite3_close_v2(handle)
    }

    func execute(_ sql: String) throws {
        let status = sqlite3_exec(handle, sql, nil, nil, nil)
        guard status == SQLITE_OK else { throw Failure.statement(status) }
    }

    func run(_ sql: String, _ values: [Value] = []) throws {
        _ = try query(sql, values) { _ in () }
    }

    func query<Result>(_ sql: String, _ values: [Value] = [], row: (Row) -> Result?) throws -> [Result] {
        let statement = try prepared(sql)
        defer {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        }
        for (index, value) in values.enumerated() {
            let position = Int32(index + 1)
            switch value {
            case .integer(let integer): sqlite3_bind_int64(statement, position, integer)
            case .real(let real): sqlite3_bind_double(statement, position, real)
            case .text(let text): sqlite3_bind_text(statement, position, text, -1, Self.transient)
            case .null: sqlite3_bind_null(statement, position)
            }
        }
        var results: [Result] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_DONE { return results }
            guard status == SQLITE_ROW else { throw Failure.statement(status) }
            if let result = row(Row(statement: statement)) { results.append(result) }
        }
    }

    func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func prepared(_ sql: String) throws -> OpaquePointer {
        if let statement = statements[sql] { return statement }
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v3(handle, sql, -1, UInt32(SQLITE_PREPARE_PERSISTENT), &statement, nil)
        guard status == SQLITE_OK, let statement else { throw Failure.statement(status) }
        statements[sql] = statement
        return statement
    }
}
