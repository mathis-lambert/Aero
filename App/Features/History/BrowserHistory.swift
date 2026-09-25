import BrowserCore
import BrowserStorage
import Foundation

/// The app's access to history. Writes run in the order they were made (a title update never
/// overtakes the visit it belongs to) and are best effort: when the store is unavailable,
/// browsing continues and the History page explains why.
@MainActor
final class BrowserHistory {
    /// Titles wait this long so a page that animates its title writes once, with its latest title.
    private static let titleDelay = Duration.seconds(2)

    private let store: HistoryStore
    private var lastWrite: Task<Void, Never>?
    private var pendingTitles: [UUID: [URL: String]] = [:]

    init(store: HistoryStore) {
        self.store = store
    }

    func recordVisit(to url: URL, profileID: UUID) {
        write { try await $0.recordVisit(to: url, title: nil, profileID: profileID) }
    }

    func updateTitle(_ title: String, for url: URL, profileID: UUID) {
        let isScheduled = !pendingTitles.isEmpty
        pendingTitles[profileID, default: [:]][url] = title
        guard !isScheduled else { return }
        Task {
            try? await Task.sleep(for: Self.titleDelay)
            writePendingTitles()
        }
    }

    func delete(_ ids: some Collection<HistoryEntry.ID>, profileID: UUID) {
        let ids = Array(ids)
        write { try await $0.delete(ids, profileID: profileID) }
    }

    func clear(profileID: UUID, since date: Date?) {
        write { try await $0.clear(profileID: profileID, since: date) }
    }

    /// Waits for earlier writes, titles included, so the result shows them.
    func entries(profileID: UUID, matching query: String, before date: Date? = nil) async throws -> [HistoryEntry] {
        writePendingTitles()
        await lastWrite?.value
        return try await store.entries(profileID: profileID, matching: query, before: date)
    }

    private func writePendingTitles() {
        guard !pendingTitles.isEmpty else { return }
        let titles = pendingTitles
        pendingTitles = [:]
        write { store in
            for (profileID, profileTitles) in titles { try await store.updateTitles(profileTitles, profileID: profileID) }
        }
    }

    private func write(_ operation: @escaping @Sendable (HistoryStore) async throws -> Void) {
        let previous = lastWrite
        lastWrite = Task { [store] in
            await previous?.value
            try? await operation(store)
        }
    }
}
