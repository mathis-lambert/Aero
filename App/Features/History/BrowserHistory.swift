import BrowserCore
import BrowserStorage
import Foundation
import Observation

/// The app's access to history. Writes run in the order they were made (a title update never
/// overtakes the visit it belongs to) and are best effort: when the store is unavailable,
/// browsing continues and the History window explains why.
@MainActor @Observable
final class BrowserHistory {
    /// Increments after each completed write, so an open History window can refresh.
    private(set) var revision = 0
    @ObservationIgnored private let store: HistoryStore
    @ObservationIgnored private var lastWrite: Task<Void, Never>?

    init(store: HistoryStore) {
        self.store = store
    }

    func recordVisit(to url: URL, profileID: UUID) {
        write { try await $0.recordVisit(to: url, title: nil, profileID: profileID) }
    }

    func updateTitle(_ title: String, for url: URL, profileID: UUID) {
        write { try await $0.updateTitle(title, for: url, profileID: profileID) }
    }

    func delete(_ ids: some Collection<HistoryEntry.ID>, profileID: UUID) {
        let ids = Array(ids)
        write { try await $0.delete(ids, profileID: profileID) }
    }

    func clear(profileID: UUID, since date: Date?) {
        write { try await $0.clear(profileID: profileID, since: date) }
    }

    func entries(profileID: UUID, matching query: String, before date: Date? = nil) async throws -> [HistoryEntry] {
        await lastWrite?.value
        return try await store.entries(profileID: profileID, matching: query, before: date)
    }

    private func write(_ operation: @escaping @Sendable (HistoryStore) async throws -> Void) {
        let previous = lastWrite
        lastWrite = Task { [store] in
            await previous?.value
            do { try await operation(store) } catch { return }
            revision += 1
        }
    }
}
