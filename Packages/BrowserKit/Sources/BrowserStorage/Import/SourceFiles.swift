import Foundation

/// Reading another application's files: never writing to them, and reporting macOS's refusals as such.
enum SourceFiles {
    static func data(_ file: URL) throws -> Data {
        do { return try Data(contentsOf: file) } catch let error as CocoaError where error.code == .fileReadNoPermission {
            throw BrowserImportError.accessDenied
        } catch { throw BrowserImportError.unreadable }
    }

    /// Opens a copy of another application's SQLite database, which it may keep locked while it runs, and removes
    /// the copy afterwards.
    static func database<Result>(_ file: URL, _ body: (SQLiteDatabase) throws -> Result) throws -> Result {
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("aero-import-\(UUID().uuidString)")
        defer {
            for suffix in ["", "-wal", "-shm", "-journal"] { try? FileManager.default.removeItem(at: URL(fileURLWithPath: copy.path + suffix)) }
        }
        do {
            try FileManager.default.copyItem(at: file, to: copy)
            for suffix in ["-wal", "-journal"] where FileManager.default.fileExists(atPath: file.path + suffix) {
                try FileManager.default.copyItem(at: URL(fileURLWithPath: file.path + suffix), to: URL(fileURLWithPath: copy.path + suffix))
            }
        } catch let error as CocoaError where error.code == .fileReadNoPermission {
            throw BrowserImportError.accessDenied
        } catch { throw BrowserImportError.unreadable }
        do {
            return try body(try SQLiteDatabase(file: copy, readOnly: true))
        } catch let error as BrowserImportError { throw error } catch { throw BrowserImportError.unreadable }
    }
}
