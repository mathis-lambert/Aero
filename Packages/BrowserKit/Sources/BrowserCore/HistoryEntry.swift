import Foundation

/// A page of a profile's history, at its most recent visit.
public struct HistoryEntry: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let url: URL
    public let title: String
    public let lastVisit: Date

    public struct Cursor: Sendable {
        public let date: Date
        public let id: Int64
    }
    public var cursor: Cursor { Cursor(date: lastVisit, id: id) }

    package init(id: Int64, url: URL, title: String, lastVisit: Date) {
        self.id = id
        self.url = url
        self.title = title
        self.lastVisit = lastVisit
    }
}
