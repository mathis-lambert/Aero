import Foundation

/// A folder of favorites in the sidebar.
public struct TabGroup: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var isCollapsed: Bool
    /// How many loose favorites of its space are listed above it (`BrowserSession.pinned(in:)`).
    public package(set) var slot: Int
    package init(id: UUID, name: String, isCollapsed: Bool, slot: Int = 0) {
        self.id = id; self.name = name; self.isCollapsed = isCollapsed; self.slot = slot
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
    public var place: TabPlace

    public init(id: UUID = UUID(), spaceID: UUID, url: URL, title: String = "", name: String? = nil, place: TabPlace = .open) {
        self.id = id
        self.spaceID = spaceID
        self.url = url
        self.title = title
        self.name = name
        self.place = place
    }

    public var isFavorite: Bool { place.isFavorite }
}
