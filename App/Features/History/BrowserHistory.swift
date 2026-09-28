import BrowserCore
import BrowserStorage
import Foundation
import Observation

/// Serial mutation order with observable write health. Explicit user deletions always await commit.
@MainActor @Observable
final class BrowserHistory {
    private static let titleDelay = Duration.seconds(2)
    @ObservationIgnored private let store: HistoryStore
    @ObservationIgnored private var lastWrite: Task<Void, any Error>?
    @ObservationIgnored private var titleTask: Task<Void, Never>?
    @ObservationIgnored private var pendingTitles: [UUID: [URL: String]] = [:]
    @ObservationIgnored private var pendingWrites: [@Sendable (HistoryStore) async throws -> Void] = []
    private(set) var writeFailed = false

    init(store: HistoryStore) { self.store = store }
    isolated deinit { titleTask?.cancel() }

    func recordVisit(to url: URL, profileID: UUID) {
        let date = Date.now
        _ = enqueue { try await $0.recordVisit(to: url, title: nil, profileID: profileID, at: date) }
    }

    func updateTitle(_ title: String, for url: URL, profileID: UUID) {
        pendingTitles[profileID, default: [:]][url] = title
        guard titleTask == nil else { return }
        titleTask = Task { [weak self] in
            do { try await Task.sleep(for: Self.titleDelay) } catch { return }
            self?.writePendingTitles()
        }
    }

    func delete(_ ids: some Collection<HistoryEntry.ID>, profileID: UUID) async throws {
        let ids = Array(ids)
        try await enqueue { try await $0.delete(ids, profileID: profileID) }.value
    }

    func clear(profileID: UUID, since date: Date?) async throws {
        // Do not let pending titles repopulate metadata after explicit erasure.
        pendingTitles[profileID] = nil
        try await enqueue { try await $0.clear(profileID: profileID, since: date) }.value
    }

    func compact() async throws {
        try await enqueue { try await $0.compact() }.value
    }

    func entries(profileID: UUID, matching query: String, before cursor: HistoryEntry.Cursor? = nil,
                 limit: Int = HistoryStore.pageSize) async throws -> [HistoryEntry] {
        writePendingTitles()
        // Reads remain available after failed recording; writeFailed explains that condition.
        _ = await lastWrite?.result
        return try await store.entries(profileID: profileID, matching: query, before: cursor, limit: limit)
    }

    func flush() async throws {
        writePendingTitles()
        try await enqueue().value
    }

    private func writePendingTitles() {
        titleTask?.cancel(); titleTask = nil
        guard !pendingTitles.isEmpty else { return }
        let titles = pendingTitles
        pendingTitles = [:]
        _ = enqueue { store in
            for (profileID, values) in titles { try await store.updateTitles(values, profileID: profileID) }
        }
    }

    private func enqueue(_ operation: (@Sendable (HistoryStore) async throws -> Void)? = nil) -> Task<Void, any Error> {
        let previous = lastWrite
        let task = Task { [store] in
            _ = await previous?.result
            if let operation { pendingWrites.append(operation) }
            do {
                // Retain failures in order: a later clear must run after a retried visit.
                while let pending = pendingWrites.first {
                    try await pending(store)
                    pendingWrites.removeFirst()
                }
                writeFailed = false
            }
            catch { writeFailed = true; throw error }
        }
        lastWrite = task
        return task
    }
}
