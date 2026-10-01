import AppKit

/// The general pasteboard is shared by tests running in parallel, and by the person's own apps: one test uses it at a
/// time, and what it held is put back afterwards.
@MainActor
enum SharedPasteboard {
    private static var isInUse = false

    static func use<T>(_ body: (NSPasteboard) async throws -> T) async throws -> T {
        while isInUse { try await Task.sleep(for: .milliseconds(20)) }
        isInUse = true
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.string(forType: .string)
        defer {
            pasteboard.clearContents()
            if let saved { pasteboard.setString(saved, forType: .string) }
            isInUse = false
        }
        return try await body(pasteboard)
    }
}
