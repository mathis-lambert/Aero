import BrowserCore
import Foundation

/// The application coordinates durable records with live resources owned by WebKit.
extension BrowserModel {
    func commitStructure(_ change: (inout BrowserSession) throws -> Void) async throws {
        await waitForPendingSave()
        var candidate = session
        try change(&candidate)
        try candidate.validate()
        revision += 1
        try await store.save(candidate, revision: revision)
        // Page metadata may arrive while SQLite is committing. Keep it for unchanged records.
        candidate.mergePageMetadata(from: session)
        session = candidate
        persist()
    }

    func structureFailure(_ message: String = String(localized: "Changes could not be saved. Check that there is enough disk space and try again.")) {
        present(.error(message))
    }
}
