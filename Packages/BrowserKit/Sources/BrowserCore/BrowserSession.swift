import Foundation

public enum SessionError: Error, Equatable {
    case invalidName, invalidEmoji, missingProfile, inconsistentData
    case missingSpace, lastSpace, lastProfile, profileInUse
}

/// Durable state only. Window selection and loaded web pages have separate owners.
public struct BrowserSession: Equatable, Sendable {
    public private(set) var profiles: [BrowserProfile]
    public private(set) var spaces: [BrowserSpace]
    public private(set) var tabs: [BrowserTab]

    public init(profileName: String, spaceName: String = "Main") {
        let profile = BrowserProfile(name: profileName)
        profiles = [profile]
        spaces = [BrowserSpace(profileID: profile.id, name: spaceName)]
        tabs = []
    }

    @discardableResult
    public mutating func addProfile(name: String) throws -> BrowserProfile {
        let profile = BrowserProfile(name: try Self.validName(name))
        profiles.append(profile)
        return profile
    }

    public mutating func editProfile(id: UUID, name: String) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id && !$0.isRemoving }) else { throw SessionError.missingProfile }
        profiles[index].name = try Self.validName(name)
    }

    @discardableResult
    public mutating func addSpace(name: String, profileID: UUID, color: SpaceColor, emoji: String? = nil) throws -> BrowserSpace {
        guard profiles.contains(where: { $0.id == profileID && !$0.isRemoving }) else { throw SessionError.missingProfile }
        let space = BrowserSpace(profileID: profileID, name: try Self.validName(name), color: color, emoji: try Self.validEmoji(emoji))
        spaces.append(space)
        return space
    }

    public mutating func editSpace(id: UUID, name: String, profileID: UUID, color: SpaceColor, emoji: String?) throws {
        guard let index = spaces.firstIndex(where: { $0.id == id }) else { throw SessionError.missingSpace }
        guard profiles.contains(where: { $0.id == profileID && !$0.isRemoving }) else { throw SessionError.missingProfile }
        let name = try Self.validName(name), emoji = try Self.validEmoji(emoji)
        spaces[index].name = name; spaces[index].color = color; spaces[index].emoji = emoji
        if spaces[index].profileID != profileID {
            // Old extension handles and page callbacks must never address the new identity.
            for tabIndex in tabs.indices where tabs[tabIndex].spaceID == id {
                let tab = tabs[tabIndex]
                tabs[tabIndex] = BrowserTab(spaceID: id, url: tab.url, title: tab.title, name: tab.name, place: tab.place)
            }
        }
        spaces[index].profileID = profileID
    }

    public mutating func removeSpace(_ id: UUID) throws {
        guard spaces.contains(where: { $0.id == id }) else { throw SessionError.missingSpace }
        guard spaces.count > 1 else { throw SessionError.lastSpace }
        spaces.removeAll { $0.id == id }
        tabs.removeAll { $0.spaceID == id }
    }

    /// Destination is an insertion boundary in the original order, as used by native lists.
    public mutating func moveSpaces(from offsets: IndexSet, to destination: Int) {
        guard !offsets.isEmpty, offsets.allSatisfy(spaces.indices.contains),
              (0...spaces.count).contains(destination) else { return }
        let moving = offsets.map { spaces[$0] }
        let insertion = destination - offsets.filter { $0 < destination }.count
        for index in offsets.reversed() { spaces.remove(at: index) }
        spaces.insert(contentsOf: moving, at: insertion)
    }

    public mutating func markProfileForRemoval(_ id: UUID) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { throw SessionError.missingProfile }
        if profiles[index].isRemoving { return }
        guard profiles.filter({ !$0.isRemoving }).count > 1 else { throw SessionError.lastProfile }
        guard !spaces.contains(where: { $0.profileID == id }) else { throw SessionError.profileInUse }
        profiles[index].isRemoving = true
    }

    public mutating func removeProfile(_ id: UUID) throws {
        guard let profile = profiles.first(where: { $0.id == id }), profile.isRemoving,
              !spaces.contains(where: { $0.profileID == id }) else { throw SessionError.profileInUse }
        profiles.removeAll { $0.id == id }
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
        if profiles[index].passwordExtension == extensionID { profiles[index].passwordExtension = nil }
    }

    /// Lets one of the profile's extensions fill its passwords, or Aero when `extensionID` is `nil`.
    public mutating func setPasswordExtension(_ extensionID: String?, profileID: UUID) {
        guard let index = profiles.firstIndex(where: { $0.id == profileID }),
              extensionID.map({ id in profiles[index].extensions.contains { $0.id == id && !$0.isRemoving } }) ?? true else { return }
        profiles[index].passwordExtension = extensionID
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

    /// Same-profile transfers keep the tab identity and its live page. Crossing profiles gives
    /// the tab a new identity. A favorite stays one, outside any group.
    public mutating func transfer(id: UUID, to spaceID: UUID) -> BrowserTab? {
        guard spaces.contains(where: { $0.id == spaceID }), let index = tabs.firstIndex(where: { $0.id == id }),
              tabs[index].spaceID != spaceID else { return nil }
        let original = tabs.remove(at: index)
        let place: TabPlace = switch original.place {
        case .grid: .grid
        case .list: .list(group: nil)
        case .open: .open
        }
        let sameProfile = spaces.first { $0.id == original.spaceID }?.profileID == spaces.first { $0.id == spaceID }?.profileID
        let tab = BrowserTab(id: sameProfile ? original.id : UUID(), spaceID: spaceID, url: original.url, title: original.title, name: original.name, place: place)
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

    /// Reconcile page events received during a structural commit, only for surviving identities.
    public mutating func mergePageMetadata(from current: BrowserSession) {
        let records = Dictionary(uniqueKeysWithValues: current.tabs.map { ($0.id, $0) })
        for index in tabs.indices {
            guard let latest = records[tabs[index].id] else { continue }
            tabs[index].url = latest.url
            tabs[index].title = latest.title
        }
    }

    public func validate() throws {
        let profileIDs = Set(profiles.map(\.id))
        let spaceIDs = Set(spaces.map(\.id))
        guard profiles.contains(where: { !$0.isRemoving }), !spaces.isEmpty,
              profileIDs.count == profiles.count,
              spaceIDs.count == spaces.count,
              profiles.allSatisfy({ Set($0.extensions.map(\.id)).count == $0.extensions.count && $0.extensions.allSatisfy(\.isValid) }),
              Set(tabs.map(\.id)).count == tabs.count,
              profiles.allSatisfy({ (try? Self.validName($0.name)) == $0.name }),
              spaces.allSatisfy({ (try? Self.validName($0.name)) == $0.name && (try? Self.validEmoji($0.emoji)) == $0.emoji }),
              profiles.filter(\.isRemoving).allSatisfy({ profile in !spaces.contains { $0.profileID == profile.id } }),
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
        guard let emoji = BrowserSpace.emoji(from: value) else { throw SessionError.invalidEmoji }
        return emoji
    }

    private static func validName(_ value: String) throws -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= BrowserProfile.maximumNameLength else { throw SessionError.invalidName }
        return value
    }
}
