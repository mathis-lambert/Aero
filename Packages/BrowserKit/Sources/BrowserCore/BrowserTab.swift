import Foundation

/// A folder of favorites in the sidebar.
public struct TabGroup: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var isCollapsed: Bool
    /// How many loose favorites of its space are listed above it (`BrowserSession.pinned(in:)`).
    public package(set) var slot: Int
    /// The name of a symbol chosen to stand for it in place of a folder; the app knows the names.
    public package(set) var icon: String?
    package init(id: UUID, name: String, isCollapsed: Bool, slot: Int = 0, icon: String? = nil) {
        self.id = id; self.name = name; self.isCollapsed = isCollapsed; self.slot = slot; self.icon = icon
    }
}

/// An entry of a space's pinned list, under the grid: a loose favorite or a group, in any order.
public enum PinnedItem: Hashable, Sendable {
    case tab(UUID)
    case group(UUID)

    public var id: UUID {
        switch self {
        case .tab(let id), .group(let id): id
        }
    }
}

/// Where a tab shows in its space's sidebar.
public enum TabPlace: Hashable, Sendable {
    /// A favorite, as a tile in the grid.
    case grid
    /// A favorite, as a row under the grid: loose, or in a group of its space.
    case list(group: UUID?)
    /// An open tab: closing it removes it.
    case open

    public var isFavorite: Bool { self != .open }
}

public struct BrowserTab: Identifiable, Equatable, Sendable {
    public let id: UUID
    public package(set) var spaceID: UUID
    public var url: URL
    public var title: String
    /// The name given in the sidebar, which the page's title never replaces.
    public var name: String?
    /// A favorite keeps the page it was pinned on; an open tab has none.
    public var place: TabPlace {
        didSet { pinnedURL = place.isFavorite ? pinnedURL ?? url : nil }
    }
    /// A favorite's own page, which browsing elsewhere in the tab never replaces (docs/BROWSING.md › Pinned pages).
    public package(set) var pinnedURL: URL?

    public init(id: UUID = UUID(), spaceID: UUID, url: URL, title: String = "", name: String? = nil, place: TabPlace = .open,
                pinnedURL: URL? = nil) {
        self.id = id
        self.spaceID = spaceID
        self.url = url
        self.title = title
        self.name = name
        self.place = place
        self.pinnedURL = place.isFavorite ? pinnedURL ?? url : nil
    }

    public var isFavorite: Bool { place.isFavorite }

    /// A favorite showing another page than its own. Its fragment, and a path's trailing slash, are the same page; a
    /// browser page is one whatever its query, such as a terminal's folder.
    public var hasLeftPinnedPage: Bool {
        guard let pinnedURL else { return false }
        if let page = InternalPage(url: pinnedURL) { return InternalPage(url: url) != page }
        return Self.page(of: pinnedURL) != Self.page(of: url)
    }

    private static func page(of url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        if let path = components?.path, path.hasSuffix("/") { components?.path = String(path.dropLast()) }
        return components?.string ?? url.absoluteString
    }
}
