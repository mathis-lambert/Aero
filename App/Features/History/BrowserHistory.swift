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
    @ObservationIgnored var onVisited: ((UUID, HistoryEntry) -> Void)?
    @ObservationIgnored var onRemoved: ((UUID, [URL], Bool) -> Void)?

    init(store: HistoryStore) { self.store = store }
    isolated deinit { titleTask?.cancel() }

    func recordVisit(to url: URL, profileID: UUID, transition: HistoryTransition = .autoTopLevel, referrer: URL? = nil) {
        let date = Date.now
        _ = enqueue { [weak self] store in
            if let entry = try await store.recordVisit(to: url, title: nil, profileID: profileID, at: date, transition: transition, referrer: referrer) {
                await self?.didRecord(entry, profileID: profileID)
            }
        }
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
        try await enqueue { [weak self] store in
            let urls = try await store.delete(ids, profileID: profileID)
            await self?.didRemove(urls, profileID: profileID, all: false)
        }.value
    }

    func clear(profileID: UUID, since date: Date?) async throws {
        // Do not let pending titles repopulate metadata after explicit erasure.
        pendingTitles[profileID] = nil
        try await enqueue { [weak self] store in
            if let date {
                let urls = try await store.deleteVisits(profileID: profileID, from: date, through: .distantFuture)
                await self?.didRemove(urls, profileID: profileID, all: false)
            } else {
                try await store.clear(profileID: profileID, since: nil)
                await self?.didRemove([], profileID: profileID, all: true)
            }
        }.value
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

    /// Imported pages, queued after pending writes like any other history change (docs/ONBOARDING.md).
    func importPages(_ pages: [ImportedPage], profileID: UUID) async throws {
        try await enqueue { try await $0.importPages(pages, profileID: profileID) }.value
    }

    func flush() async throws {
        writePendingTitles()
        try await enqueue().value
    }

    func search(profileID: UUID, text: String, since start: Date, until end: Date, limit: Int) async throws -> [HistoryEntry] {
        try await flush()
        return try await store.search(profileID: profileID, text: text, since: start, until: end, limit: limit)
    }

    func visits(to url: URL, profileID: UUID) async throws -> [HistoryVisit] {
        try await flush()
        return try await store.visits(to: url, profileID: profileID)
    }

    func mostVisited(profileID: UUID, limit: Int) async throws -> [HistoryEntry] {
        try await flush()
        return try await store.mostVisited(profileID: profileID, limit: limit)
    }

    func recentVisits(profileID: UUID, since start: Date, limit: Int) async throws -> [SiteVisit] {
        try await flush()
        return try await store.recentVisits(profileID: profileID, since: start, limit: limit)
    }

    func deleteVisits(profileID: UUID, from start: Date, through end: Date) async throws {
        try await enqueue { [weak self] store in
            let urls = try await store.deleteVisits(profileID: profileID, from: start, through: end)
            await self?.didRemove(urls, profileID: profileID, all: false)
        }.value
    }

    func delete(url: URL, profileID: UUID) async throws {
        pendingTitles[profileID]?[url] = nil
        try await enqueue { [weak self] store in
            let urls = try await store.delete(url: url, profileID: profileID)
            await self?.didRemove(urls, profileID: profileID, all: false)
        }.value
    }

    private func didRecord(_ entry: HistoryEntry, profileID: UUID) { onVisited?(profileID, entry) }
    private func didRemove(_ urls: [URL], profileID: UUID, all: Bool) {
        if all || !urls.isEmpty { onRemoved?(profileID, urls, all) }
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
