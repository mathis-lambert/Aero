import BrowserCore
import Foundation

// What an import brings, independent of the browser it came from. See docs/ONBOARDING.md › Import.

public enum BrowserImportError: Error, Equatable, Sendable {
    /// Missing, damaged, or not the expected format.
    case unreadable
    /// macOS refused access (Safari without Full Disk Access).
    case accessDenied
}

public struct ImportLimits: Sendable {
    /// Older history is not imported.
    public var since: Date
    /// Favorites per space, groups included.
    public var links: Int
    /// History pages per profile, the most recent first.
    public var pages: Int
    public var visitsPerPage: Int

    public init(since: Date, links: Int, pages: Int, visitsPerPage: Int) {
        self.since = since
        self.links = links
        self.pages = pages
        self.visitsPerPage = visitsPerPage
    }

    /// docs/ONBOARDING.md › Mapping.
    public static func standard(now: Date = .now) -> ImportLimits {
        ImportLimits(since: now.addingTimeInterval(-365 * 24 * 60 * 60), links: 10_000, pages: 100_000, visitsPerPage: 20)
    }
}

public struct ImportedLink: Equatable, Sendable {
    public let url: URL
    public let title: String
}

/// A first-level folder of the source; everything nested inside it is gathered in it, in order.
public struct ImportedGroup: Equatable, Sendable {
    public enum Title: Equatable, Sendable {
        case folder(String)
        /// The source's unnamed roots, which the app names in its language.
        case otherBookmarks, mobileBookmarks, bookmarksMenu
    }

    public let title: Title
    public var links: [ImportedLink]
}

/// A space's worth of favorites: tiles, loose rows, then groups.
public struct ImportedSpace: Equatable, Sendable {
    public var name: String?
    public var color: SpaceColor?
    public var emoji: String?
    /// Where the source shows it among all its spaces, whatever their profile.
    public var position = 0
    public var tiles: [ImportedLink] = []
    public var links: [ImportedLink] = []
    public var groups: [ImportedGroup] = []
    /// Addresses that are not websites, and favorites beyond the limit.
    public var skipped = 0

    public var allLinks: [ImportedLink] { tiles + links + groups.flatMap(\.links) }
}

public struct ImportedPage: Equatable, Sendable {
    public let url: URL
    public let title: String
    public let lastVisit: Date
    /// Newest first.
    public let visits: [Date]

    package init(url: URL, title: String, lastVisit: Date, visits: [Date]) {
        self.url = url
        self.title = title
        self.lastVisit = lastVisit
        self.visits = visits
    }
}

public struct ImportedHistory: Equatable, Sendable {
    public var pages: [ImportedPage] = []
    public var skipped = 0
}

/// One profile of the source browser: it becomes one Aero profile, with its spaces.
public struct ImportedProfile: Identifiable, Sendable {
    /// The profile folder's path, the same as `ChromiumProfile.id` for its passwords.
    public let id: String
    public let name: String
    public var spaces: [ImportedSpace]
    public var history: ImportedHistory
    /// The source's own icons for the favorites, by page address, as it stored them.
    public var icons: [URL: Data] = [:]
}
