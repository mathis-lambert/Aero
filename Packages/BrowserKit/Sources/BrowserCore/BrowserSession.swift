import Foundation

public enum ProfileColor: String, Codable, CaseIterable, Sendable {
    case terracotta, moss, ocean, plum, graphite
}

public struct BrowserProfile: Identifiable, Codable, Equatable, Sendable {
    public static let maximumNameLength = 40
    public let id: UUID
    public var name: String
    public var color: ProfileColor

    public init(id: UUID = UUID(), name: String, color: ProfileColor = .terracotta) {
        self.id = id
        self.name = name
        self.color = color
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
    case invalidProfileName, missingProfile, inconsistentData
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
    public mutating func addProfile(name: String, color: ProfileColor) throws -> BrowserProfile {
        let profile = BrowserProfile(name: try Self.validName(name), color: color)
        profiles.append(profile)
        spaces.append(BrowserSpace(profileID: profile.id))
        return profile
    }

    public mutating func editProfile(id: UUID, name: String, color: ProfileColor) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { throw SessionError.missingProfile }
        let name = try Self.validName(name)
        profiles[index].name = name
        profiles[index].color = color
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
              profiles.allSatisfy({ (try? Self.validName($0.name)) == $0.name }),
              profiles.allSatisfy({ profile in spaces.contains { $0.profileID == profile.id } }),
              spaces.allSatisfy({ profileIDs.contains($0.profileID) }),
              tabs.allSatisfy({ spaceIDs.contains($0.spaceID) && NavigationInput.isTabURL($0.url) })
        else { throw SessionError.inconsistentData }
    }

    private static func validName(_ value: String) throws -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= BrowserProfile.maximumNameLength else { throw SessionError.invalidProfileName }
        return value
    }
}
