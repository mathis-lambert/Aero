import Foundation

public enum ProfileColor: String, CaseIterable, Sendable {
    case terracotta, moss, ocean, plum, graphite
}

public struct BrowserProfile: Identifiable, Equatable, Sendable {
    public static let maximumNameLength = 40
    public let id: UUID
    public var name: String
    public var color: ProfileColor
    /// Stands for the profile in the sidebar; without one, its color does.
    public var emoji: String?
    /// Saved answers by origin; an origin without one is left out.
    public package(set) var sitePermissions: [SiteOrigin: [SitePermission: SiteDecision]]
    public package(set) var extensions: [InstalledExtension]

    public init(id: UUID = UUID(), name: String, color: ProfileColor = .terracotta, emoji: String? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.emoji = emoji
        sitePermissions = [:]
        extensions = []
    }

    public func decision(for permission: SitePermission, at origin: SiteOrigin) -> SiteDecision? {
        sitePermissions[origin]?[permission]
    }

    /// The single emoji `text` holds, ignoring surrounding spaces, or `nil`. Sequences (flags, skin
    /// tones, families, keycaps) count as one; digits and symbols that only have an emoji form with
    /// a variation selector need it.
    public static func emoji(from text: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let scalars = value.unicodeScalars
        guard value.count == 1, let first = scalars.first, first.properties.isEmoji, !first.properties.isEmojiModifier else { return nil }
        return scalars.contains(where: \.properties.isEmojiPresentation) || scalars.count > 1 ? value : nil
    }
}

public struct BrowserSpace: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let profileID: UUID
    /// Groups of favorites, in the sidebar's order.
    public package(set) var groups: [TabGroup]

    public init(id: UUID = UUID(), profileID: UUID) {
        self.id = id
        self.profileID = profileID
        groups = []
    }
}

/// A folder of favorites in the sidebar.
public struct TabGroup: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var isCollapsed: Bool
    package init(id: UUID, name: String, isCollapsed: Bool) {
        self.id = id; self.name = name; self.isCollapsed = isCollapsed
    }
}

/// Where a tab shows in its profile's sidebar.
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
    public let spaceID: UUID
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

public enum SessionError: Error, Equatable {
    case invalidProfileName, invalidEmoji, missingProfile, inconsistentData
}

/// Durable state only. Window selection and loaded web pages have separate owners.
public struct BrowserSession: Equatable, Sendable {
    public private(set) var profiles: [BrowserProfile]
    public private(set) var spaces: [BrowserSpace]
    public private(set) var tabs: [BrowserTab]

    public init(profileName: String) {
        let profile = BrowserProfile(name: profileName)
        profiles = [profile]
        spaces = [BrowserSpace(profileID: profile.id)]
        tabs = []
    }

    @discardableResult
    public mutating func addProfile(name: String, color: ProfileColor, emoji: String? = nil) throws -> BrowserProfile {
        let profile = BrowserProfile(name: try Self.validName(name), color: color, emoji: try Self.validEmoji(emoji))
        profiles.append(profile)
        spaces.append(BrowserSpace(profileID: profile.id))
        return profile
    }

    public mutating func editProfile(id: UUID, name: String, color: ProfileColor, emoji: String?) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { throw SessionError.missingProfile }
        let name = try Self.validName(name)
        let emoji = try Self.validEmoji(emoji)
        profiles[index].name = name
        profiles[index].color = color
        profiles[index].emoji = emoji
    }

    package init(profiles: [BrowserProfile], spaces: [BrowserSpace], tabs: [BrowserTab]) {
        self.profiles = profiles
        self.spaces = spaces
        self.tabs = tabs
    }

    /// Saves `decision` for the profile, or forgets the saved one when it is `nil`.
    public mutating func setDecision(_ decision: SiteDecision?, for permission: SitePermission, at origin: SiteOrigin, profileID: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[index].sitePermissions[origin, default: [:]][permission] = decision
        if profiles[index].sitePermissions[origin]?.isEmpty == true { profiles[index].sitePermissions[origin] = nil }
    }

    /// Adds the extension to the profile, or replaces the record with the same identifier.
    public mutating func setExtension(_ record: InstalledExtension, profileID: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        if let existing = profiles[index].extensions.firstIndex(where: { $0.id == record.id }) { profiles[index].extensions[existing] = record }
        else { profiles[index].extensions.append(record) }
    }

    public mutating func removeExtension(_ extensionID: String, profileID: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[index].extensions.removeAll { $0.id == extensionID }
    }

    public mutating func resetPermissions(at origin: SiteOrigin, profileID: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[index].sitePermissions[origin] = nil
    }

    public mutating func open(_ url: URL, in spaceID: UUID) -> BrowserTab? {
        guard spaces.contains(where: { $0.id == spaceID }) else { return nil }
        let tab = BrowserTab(spaceID: spaceID, url: url)
        tabs.append(tab)
        return tab
    }

    public mutating func updateTab(id: UUID, url: URL, title: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].url = url
        tabs[index].title = title
    }

    /// Moves a tab before another tab of its space, or to the end, into `place`. Tabs never change
    /// space this way, and only enter a group of their own space.
    public mutating func move(id: UUID, to place: TabPlace, before targetID: UUID?) -> Bool {
        guard id != targetID, let index = tabs.firstIndex(where: { $0.id == id }) else { return false }
        let spaceID = tabs[index].spaceID
        if let targetID, tabs.first(where: { $0.id == targetID })?.spaceID != spaceID { return false }
        guard isValid(place, in: spaceID) else { return false }
        var tab = tabs.remove(at: index)
        tab.place = place
        let destination = targetID.flatMap { target in tabs.firstIndex { $0.id == target } } ?? tabs.endIndex
        tabs.insert(tab, at: destination)
        return true
    }

    /// A blank name gives back the page's title.
    public mutating func rename(id: UUID, to name: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].name = Self.trimmed(name)
    }

    /// An open tab with the original's address and name: after it, or after the open tabs when
    /// the original is a favorite.
    public mutating func duplicate(id: UUID) -> BrowserTab? {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return nil }
        let original = tabs[index]
        let copy = BrowserTab(spaceID: original.spaceID, url: original.url, title: original.title, name: original.name)
        tabs.insert(copy, at: original.isFavorite ? tabs.endIndex : index + 1)
        return copy
    }

    /// Replaces the tab with a new one at the end of another space, so nothing of the first
    /// profile's page carries over. A favorite stays one, outside any group.
    public mutating func transfer(id: UUID, to spaceID: UUID) -> BrowserTab? {
        guard spaces.contains(where: { $0.id == spaceID }), let index = tabs.firstIndex(where: { $0.id == id }),
              tabs[index].spaceID != spaceID else { return nil }
        let original = tabs.remove(at: index)
        let place: TabPlace = switch original.place {
        case .grid: .grid
        case .list: .list(group: nil)
        case .open: .open
        }
        let tab = BrowserTab(spaceID: spaceID, url: original.url, title: original.title, name: original.name, place: place)
        tabs.append(tab)
        return tab
    }

    public mutating func addGroup(named name: String, in spaceID: UUID) -> TabGroup? {
        guard let index = spaces.firstIndex(where: { $0.id == spaceID }), let name = Self.trimmed(name) else { return nil }
        let group = TabGroup(id: UUID(), name: name, isCollapsed: false)
        spaces[index].groups.append(group)
        return group
    }

    /// A blank name keeps the current one.
    public mutating func renameGroup(id: UUID, to name: String) {
        guard let name = Self.trimmed(name) else { return }
        updateGroup(id) { $0.name = name }
    }

    public mutating func setGroupCollapsed(id: UUID, _ collapsed: Bool) {
        updateGroup(id) { $0.isCollapsed = collapsed }
    }

    /// Its favorites stay, as loose rows.
    public mutating func removeGroup(id: UUID) {
        for index in spaces.indices { spaces[index].groups.removeAll { $0.id == id } }
        for index in tabs.indices where tabs[index].place == .list(group: id) { tabs[index].place = .list(group: nil) }
    }

    private mutating func updateGroup(_ id: UUID, _ change: (inout TabGroup) -> Void) {
        for space in spaces.indices {
            if let group = spaces[space].groups.firstIndex(where: { $0.id == id }) { change(&spaces[space].groups[group]) }
        }
    }

    private func isValid(_ place: TabPlace, in spaceID: UUID) -> Bool {
        guard case .list(let group?) = place else { return true }
        return spaces.first { $0.id == spaceID }?.groups.contains { $0.id == group } == true
    }

    @discardableResult
    public mutating func close(id: UUID) -> BrowserTab? {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return nil }
        return tabs.remove(at: index)
    }

    public mutating func restore(_ tab: BrowserTab) {
        guard spaces.contains(where: { $0.id == tab.spaceID }), !tabs.contains(where: { $0.id == tab.id }) else { return }
        tabs.append(tab)
    }

    public func validate() throws {
        let profileIDs = Set(profiles.map(\.id))
        let spaceIDs = Set(spaces.map(\.id))
        guard !profiles.isEmpty,
              profileIDs.count == profiles.count,
              spaceIDs.count == spaces.count,
              Set(spaces.map(\.profileID)).count == spaces.count,
              profiles.allSatisfy({ Set($0.extensions.map(\.id)).count == $0.extensions.count && $0.extensions.allSatisfy(\.isValid) }),
              Set(tabs.map(\.id)).count == tabs.count,
              profiles.allSatisfy({ (try? Self.validName($0.name)) == $0.name && (try? Self.validEmoji($0.emoji)) == $0.emoji }),
              profiles.allSatisfy({ profile in spaces.contains { $0.profileID == profile.id } }),
              spaces.allSatisfy({ profileIDs.contains($0.profileID) }),
              Set(spaces.flatMap(\.groups).map(\.id)).count == spaces.flatMap(\.groups).count,
              spaces.allSatisfy({ $0.groups.allSatisfy { Self.trimmed($0.name) == $0.name } }),
              tabs.allSatisfy({ spaceIDs.contains($0.spaceID) && NavigationInput.isTabURL($0.url) && isValid($0.place, in: $0.spaceID) }),
              tabs.allSatisfy({ $0.name.map { Self.trimmed($0) == $0 } ?? true })
        else { throw SessionError.inconsistentData }
    }

    private static func trimmed(_ value: String) -> String? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func validEmoji(_ value: String?) throws -> String? {
        guard let value else { return nil }
        guard let emoji = BrowserProfile.emoji(from: value) else { throw SessionError.invalidEmoji }
        return emoji
    }

    private static func validName(_ value: String) throws -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= BrowserProfile.maximumNameLength else { throw SessionError.invalidProfileName }
        return value
    }
}
