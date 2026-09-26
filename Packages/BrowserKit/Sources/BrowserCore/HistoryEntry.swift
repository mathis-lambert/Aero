import Foundation

/// A page of a profile's history, at its most recent visit.
public struct HistoryEntry: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let url: URL
    public let title: String
    public let lastVisit: Date

    package init(id: Int64, url: URL, title: String, lastVisit: Date) {
        self.id = id
        self.url = url
        self.title = title
        self.lastVisit = lastVisit
    }
}
