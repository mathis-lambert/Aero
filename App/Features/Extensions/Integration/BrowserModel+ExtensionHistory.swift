import BrowserCore
import Foundation

extension BrowserModel {
    func historyEntries(inProfile profileID: UUID, text: String, since start: Date, until end: Date, limit: Int) async throws -> [HistoryEntry] {
        try requireHistoryProfile(profileID)
        return try await history.search(profileID: profileID, text: text, since: start, until: end, limit: limit)
    }

    func historyVisits(to url: URL, inProfile profileID: UUID) async throws -> [HistoryVisit] {
        try requireHistoryProfile(profileID)
        return try await history.visits(to: url, profileID: profileID)
    }

    func addHistoryURL(_ url: URL, inProfile profileID: UUID) async throws {
        try requireHistoryProfile(profileID)
        history.recordVisit(to: url, profileID: profileID, transition: .link)
        try await history.flush()
    }

    func removeHistoryURL(_ url: URL, inProfile profileID: UUID) async throws {
        try requireHistoryProfile(profileID)
        try await history.delete(url: url, profileID: profileID)
    }

    func removeHistory(inProfile profileID: UUID, from start: Date?, through end: Date?) async throws {
        try requireHistoryProfile(profileID)
        if let start, let end { try await history.deleteVisits(profileID: profileID, from: start, through: end) }
        else { try await history.clear(profileID: profileID, since: start) }
    }

    func topSites(inProfile profileID: UUID) async throws -> [HistoryEntry] {
        try requireHistoryProfile(profileID)
        return try await history.mostVisited(profileID: profileID, limit: 20)
    }

    private func requireHistoryProfile(_ profileID: UUID) throws {
        guard session.profiles.contains(where: { $0.id == profileID && !$0.isRemoving }) else { throw CancellationError() }
    }
}
