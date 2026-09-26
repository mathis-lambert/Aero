import Foundation

public enum ProfileColor: String, Codable, CaseIterable, Sendable {
    case terracotta, moss, ocean, plum, graphite
}

public struct BrowserProfile: Identifiable, Codable, Equatable, Sendable {
    public static let maximumNameLength = 40
    public let id: UUID
    public var name: String
    public var color: ProfileColor
    /// Stands for the profile in the sidebar; without one, its color does.
    public var emoji: String?
    /// Saved answers by origin; an origin without one is left out.
    public internal(set) var sitePermissions: [SiteOrigin: [SitePermission: SiteDecision]]

    public init(id: UUID = UUID(), name: String, color: ProfileColor = .terracotta, emoji: String? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.emoji = emoji
        sitePermissions = [:]
    }

    /// Like the emoji, the permissions are optional in the file: a profile that never saved one has none.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        color = try container.decode(ProfileColor.self, forKey: .color)
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji)
        sitePermissions = try container.decodeIfPresent([SiteOrigin: [SitePermission: SiteDecision]].self, forKey: .sitePermissions) ?? [:]
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

public struct BrowserSpace: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let profileID: UUID

    public init(id: UUID = UUID(), profileID: UUID) {
        self.id = id
        self.profileID = profileID
    }
}

public struct BrowserTab: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let spaceID: UUID
    public var url: URL
    public var title: String
    public var isPinned: Bool

    public init(id: UUID = UUID(), spaceID: UUID, url: URL, title: String = "", isPinned: Bool = false) {
        self.id = id
        self.spaceID = spaceID
        self.url = url
        self.title = title
        self.isPinned = isPinned
    }
}

public enum SessionError: Error, Equatable {
    case invalidProfileName, invalidEmoji, missingProfile, inconsistentData
}

/// Durable state only. Window selection and loaded web pages have separate owners.
public struct BrowserSession: Codable, Equatable, Sendable {
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

    /// Saves `decision` for the profile, or forgets the saved one when it is `nil`.
    public mutating func setDecision(_ decision: SiteDecision?, for permission: SitePermission, at origin: SiteOrigin, profileID: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[index].sitePermissions[origin, default: [:]][permission] = decision
        if profiles[index].sitePermissions[origin]?.isEmpty == true { profiles[index].sitePermissions[origin] = nil }
    }

    public mutating func resetPermissions(at origin: SiteOrigin, profileID: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return }
        profiles[index].sitePermissions[origin] = nil
    }

    @discardableResult
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

    public mutating func togglePin(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].isPinned.toggle()
    }

    /// Moves a tab before another tab of its space, or to the end, and sets its pin state.
    /// Tabs never change space this way.
    @discardableResult
    public mutating func moveTab(id: UUID, before targetID: UUID?, pinned: Bool) -> Bool {
        guard id != targetID, let index = tabs.firstIndex(where: { $0.id == id }) else { return false }
        if let targetID, tabs.first(where: { $0.id == targetID })?.spaceID != tabs[index].spaceID { return false }
        var tab = tabs.remove(at: index)
        tab.isPinned = pinned
        let destination = targetID.flatMap { target in tabs.firstIndex { $0.id == target } } ?? tabs.endIndex
        tabs.insert(tab, at: destination)
        return true
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
              Set(tabs.map(\.id)).count == tabs.count,
              profiles.allSatisfy({ (try? Self.validName($0.name)) == $0.name && (try? Self.validEmoji($0.emoji)) == $0.emoji }),
              profiles.allSatisfy({ profile in spaces.contains { $0.profileID == profile.id } }),
              spaces.allSatisfy({ profileIDs.contains($0.profileID) }),
              tabs.allSatisfy({ spaceIDs.contains($0.spaceID) && NavigationInput.isTabURL($0.url) })
        else { throw SessionError.inconsistentData }
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
