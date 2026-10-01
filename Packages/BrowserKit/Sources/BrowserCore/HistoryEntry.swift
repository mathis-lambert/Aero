import Foundation

/// A page of a profile's history, at its most recent visit.
public struct HistoryEntry: Identifiable, Equatable, Sendable {
    public let id: Int64
    public let url: URL
    public let title: String
    public let lastVisit: Date
    public let visitCount: Int

    public struct Cursor: Sendable {
        public let date: Date
        public let id: Int64
    }
    public var cursor: Cursor { Cursor(date: lastVisit, id: id) }

    package init(id: Int64, url: URL, title: String, lastVisit: Date, visitCount: Int = 0) {
        self.id = id
        self.url = url
        self.title = title
        self.lastVisit = lastVisit
        self.visitCount = visitCount
    }
}

public struct HistoryVisit: Equatable, Sendable {
    public let id: Int64
    public let pageID: Int64
    public let date: Date
    public let transition: HistoryTransition
    public let referringVisitID: Int64?

    package init(id: Int64, pageID: Int64, date: Date, transition: HistoryTransition, referringVisitID: Int64?) {
        self.id = id
        self.pageID = pageID
        self.date = date
        self.transition = transition
        self.referringVisitID = referringVisitID
    }
}

public enum HistoryTransition: String, Sendable {
    case link, typed, reload
    case formSubmit = "form_submit"
    case autoTopLevel = "auto_toplevel"
}

/// Native main-frame provenance for a committed visit, independent of a tab's durable record.
public struct HistoryNavigation: Sendable {
    public let url: URL
    public let transition: HistoryTransition
    public let referrer: URL?
    /// The address changed within the document, as with `pushState` or a fragment; `referrer` is the previous one.
    public let isWithinDocument: Bool

    public init(url: URL, transition: HistoryTransition = .autoTopLevel, referrer: URL? = nil, isWithinDocument: Bool = false) {
        self.url = url
        self.transition = transition
        self.referrer = referrer
        self.isWithinDocument = isWithinDocument
    }
}
