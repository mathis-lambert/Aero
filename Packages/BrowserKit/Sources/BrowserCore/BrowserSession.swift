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
    /// Open tabs shown side by side (docs/SPLIT_VIEW.md); a tab is in one at most.
    public private(set) var splits: [TabSplit] = []

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
            var renewed: [UUID: UUID] = [:]
            for tabIndex in tabs.indices where tabs[tabIndex].spaceID == id {
                let tab = tabs[tabIndex]
                tabs[tabIndex] = BrowserTab(spaceID: id, url: tab.url, title: tab.title, name: tab.name, place: tab.place, pinnedURL: tab.pinnedURL)
                renewed[tab.id] = tabs[tabIndex].id
            }
            carrySplits(renewed, to: id)
        }
        spaces[index].profileID = profileID
    }

    public mutating func removeSpace(_ id: UUID) throws {
        guard spaces.contains(where: { $0.id == id }) else { throw SessionError.missingSpace }
        guard spaces.count > 1 else { throw SessionError.lastSpace }
        spaces.removeAll { $0.id == id }
        tabs.removeAll { $0.spaceID == id }
        splits.removeAll { $0.spaceID == id }
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

    package init(profiles: [BrowserProfile], spaces: [BrowserSpace], tabs: [BrowserTab], splits: [TabSplit] = []) {
        self.profiles = profiles
        self.spaces = spaces
        self.tabs = tabs
        self.splits = splits
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

    /// Moves a tab into `place` of its own space, before `targetID` or at the end. Among the pinned favorites the
    /// target may be a group as well as a tab: groups and loose favorites keep any order. Tabs never change space
    /// this way, and only enter a group of their own space. A pane of a split moves its split, which keeps its order.
    @discardableResult
    public mutating func move(id: UUID, to place: TabPlace, before targetID: UUID?) -> Bool {
        let members = split(containing: id).map(orderedPanes) ?? [id]
        if let targetID, members.contains(targetID) { return false }
        // Each before the target, or last, in turn: the panes stay together and in order.
        var moved = false
        for member in members { moved = moveTab(member, to: place, before: targetID) || moved }
        pruneSplits()
        return moved
    }

    private mutating func moveTab(_ id: UUID, to place: TabPlace, before targetID: UUID?) -> Bool {
        guard id != targetID, let index = tabs.firstIndex(where: { $0.id == id }) else { return false }
        let spaceID = tabs[index].spaceID
        guard isValid(place, in: spaceID) else { return false }
        if place == .list(group: nil) {
            var items = pinned(in: spaceID).filter { $0 != .tab(id) }
            let at = targetID.map { target in items.firstIndex { $0.id == target } } ?? items.endIndex
            guard let at else { return false }
            tabs[index].place = place
            items.insert(.tab(id), at: at)
            arrange(items, in: spaceID)
            return true
        }
        if let targetID, tabs.first(where: { $0.id == targetID })?.spaceID != spaceID { return false }
        keepingPinnedOrder(of: [spaceID]) { session in
            var tab = session.tabs.remove(at: index)
            tab.place = place
            let destination = targetID.flatMap { target in session.tabs.firstIndex { $0.id == target } } ?? session.tabs.endIndex
            session.tabs.insert(tab, at: destination)
        }
        return true
    }

    /// The favorite's own page becomes `url`; an open tab has none, and an address no tab shows is refused.
    @discardableResult
    public mutating func setPinnedURL(id: UUID, to url: URL) -> Bool {
        guard let index = tabs.firstIndex(where: { $0.id == id }), tabs[index].isFavorite, NavigationInput.isTabURL(url) else { return false }
        tabs[index].pinnedURL = url
        return true
    }

    /// The favorite's record goes back to its own page, as it shows when loaded again; its title comes with the page.
    public mutating func returnToPinnedPage(id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }), let pinnedURL = tabs[index].pinnedURL, tabs[index].hasLeftPinnedPage else { return }
        tabs[index].url = pinnedURL
        tabs[index].title = ""
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
    /// the tab a new identity. A favorite stays one, outside any group. A pane of a split takes its split along.
    /// Returns the identity of each tab that moved, by its old one.
    @discardableResult
    public mutating func transfer(id: UUID, to spaceID: UUID) -> [UUID: UUID] {
        var moved: [UUID: UUID] = [:]
        for member in split(containing: id).map(orderedPanes) ?? [id] { moved[member] = transferTab(member, to: spaceID)?.id }
        carrySplits(moved, to: spaceID)
        return moved
    }

    private mutating func transferTab(_ id: UUID, to spaceID: UUID) -> BrowserTab? {
        guard spaces.contains(where: { $0.id == spaceID }), let original = tabs.first(where: { $0.id == id }),
              original.spaceID != spaceID else { return nil }
        let place: TabPlace = switch original.place {
        case .grid: .grid
        case .list: .list(group: nil)
        case .open: .open
        }
        return keepingPinnedOrder(of: [original.spaceID, spaceID]) { $0.relocate(id, to: spaceID, place: place) }
    }

    /// Moves a group, with its tabs in their order, to another space, before `targetID` of its pinned list or last.
    /// Each tab's identity there, as `transfer` gives it, is returned by its old one.
    public mutating func transferGroup(id: UUID, to spaceID: UUID, before targetID: UUID?) -> [UUID: UUID]? {
        guard let source = spaces.firstIndex(where: { $0.groups.contains { $0.id == id } }), spaces[source].id != spaceID,
              let target = spaces.firstIndex(where: { $0.id == spaceID }),
              let index = spaces[source].groups.firstIndex(where: { $0.id == id }) else { return nil }
        var destination = pinned(in: spaceID)
        let at = targetID.map { target in destination.firstIndex { $0.id == target } } ?? destination.endIndex
        guard let at else { return nil }
        let remaining = pinned(in: spaces[source].id).filter { $0 != .group(id) }
        let members = tabs.filter { $0.place == .list(group: id) }.map(\.id)
        spaces[target].groups.append(spaces[source].groups.remove(at: index))
        var moved: [UUID: UUID] = [:]
        for member in members {
            moved[member] = relocate(member, to: spaceID, place: .list(group: id))?.id
        }
        destination.insert(.group(id), at: at)
        arrange(remaining, in: spaces[source].id)
        arrange(destination, in: spaceID)
        carrySplits(moved, to: spaceID)
        return moved
    }

    /// Same-profile moves keep the tab's identity; crossing profiles gives it a new one.
    private mutating func relocate(_ id: UUID, to spaceID: UUID, place: TabPlace) -> BrowserTab? {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return nil }
        let original = tabs.remove(at: index)
        let sameProfile = spaces.first { $0.id == original.spaceID }?.profileID == spaces.first { $0.id == spaceID }?.profileID
        let tab = BrowserTab(id: sameProfile ? original.id : UUID(), spaceID: spaceID, url: original.url, title: original.title, name: original.name,
                             place: place, pinnedURL: original.pinnedURL)
        tabs.append(tab)
        return tab
    }

    public mutating func addGroup(named name: String, in spaceID: UUID) -> TabGroup? {
        guard let index = spaces.firstIndex(where: { $0.id == spaceID }), let name = Self.trimmed(name) else { return nil }
        let loose = tabs.count { $0.spaceID == spaceID && $0.place == .list(group: nil) }
        let group = TabGroup(id: UUID(), name: name, isCollapsed: false, slot: loose)
        spaces[index].groups.append(group)
        return group
    }

    /// Moves a group before another entry of its space's pinned list, a group or a loose favorite, or last; its tabs
    /// follow it.
    @discardableResult
    public mutating func moveGroup(id: UUID, before targetID: UUID?) -> Bool {
        guard id != targetID, let spaceID = spaces.first(where: { $0.groups.contains { $0.id == id } })?.id else { return false }
        var items = pinned(in: spaceID).filter { $0 != .group(id) }
        let at = targetID.map { target in items.firstIndex { $0.id == target } } ?? items.endIndex
        guard let at else { return false }
        items.insert(.group(id), at: at)
        arrange(items, in: spaceID)
        return true
    }

    /// A space's pinned list as the sidebar shows it: each group after the number of loose favorites its slot
    /// counts, in their order. Out-of-range slots read as the nearest valid one.
    public func pinned(in spaceID: UUID) -> [PinnedItem] {
        guard let space = spaces.first(where: { $0.id == spaceID }) else { return [] }
        let loose = tabs.filter { $0.spaceID == spaceID && $0.place == .list(group: nil) }.map(\.id)
        var items: [PinnedItem] = [], next = 0
        for group in space.groups {
            let slot = min(max(group.slot, next), loose.count)
            items += loose[next..<slot].map(PinnedItem.tab)
            items.append(.group(group.id))
            next = slot
        }
        return items + loose[next...].map(PinnedItem.tab)
    }

    /// Writes a space's pinned list back: the groups' order and slots, and the loose favorites' order within the
    /// positions they already hold. `items` must hold exactly the space's groups and loose favorites.
    private mutating func arrange(_ items: [PinnedItem], in spaceID: UUID) {
        guard let space = spaces.firstIndex(where: { $0.id == spaceID }) else { return }
        let positions = tabs.indices.filter { tabs[$0].spaceID == spaceID && tabs[$0].place == .list(group: nil) }
        var groups: [TabGroup] = [], loose: [UUID] = []
        for item in items {
            switch item {
            case .tab(let id): loose.append(id)
            case .group(let id):
                guard var group = spaces[space].groups.first(where: { $0.id == id }) else { continue }
                group.slot = loose.count
                groups.append(group)
            }
        }
        guard positions.count == loose.count, groups.count == spaces[space].groups.count else { return }
        spaces[space].groups = groups
        let records = Dictionary(uniqueKeysWithValues: positions.map { (tabs[$0].id, tabs[$0]) })
        for (position, id) in zip(positions, loose) {
            if let tab = records[id] { tabs[position] = tab }
        }
    }

    /// Runs `change`, then keeps each space's pinned entries in their order, with new ones last.
    @discardableResult
    private mutating func keepingPinnedOrder<Result>(of spaceIDs: [UUID], _ change: (inout BrowserSession) -> Result) -> Result {
        let previous = spaceIDs.map { pinned(in: $0) }
        let result = change(&self)
        for (spaceID, items) in zip(spaceIDs, previous) {
            let current = pinned(in: spaceID)
            let present = Set(current)
            let kept = items.filter(present.contains)
            let known = Set(kept)
            arrange(kept + current.filter { !known.contains($0) }, in: spaceID)
        }
        return result
    }

    /// A blank name keeps the current one.
    public mutating func renameGroup(id: UUID, to name: String) {
        guard let name = Self.trimmed(name) else { return }
        updateGroup(id) { $0.name = name }
    }

    /// A blank icon gives the folder back.
    public mutating func setGroupIcon(id: UUID, to icon: String?) {
        updateGroup(id) { $0.icon = icon.flatMap(Self.trimmed) }
    }

    public mutating func setGroupCollapsed(id: UUID, _ collapsed: Bool) {
        updateGroup(id) { $0.isCollapsed = collapsed }
    }

    /// Its favorites stay where it was, as loose rows.
    public mutating func removeGroup(id: UUID) {
        guard let spaceID = spaces.first(where: { $0.groups.contains { $0.id == id } })?.id else { return }
        let members = tabs.filter { $0.place == .list(group: id) }.map { PinnedItem.tab($0.id) }
        let items = pinned(in: spaceID).flatMap { $0 == .group(id) ? members : [$0] }
        for index in tabs.indices where tabs[index].place == .list(group: id) { tabs[index].place = .list(group: nil) }
        for index in spaces.indices { spaces[index].groups.removeAll { $0.id == id } }
        arrange(items, in: spaceID)
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
        let closed = keepingPinnedOrder(of: [tabs[index].spaceID]) { $0.tabs.remove(at: index) }
        pruneSplits()
        return closed
    }

    // MARK: Splits

    public func split(containing tabID: UUID) -> TabSplit? {
        splits.first { $0.root.tabIDs.contains(tabID) }
    }

    /// Shows `tabID` beside `targetID`, in the split of `targetID`, or a new one with both. Both must be tabs of one
    /// space, and the split may hold no more than four; a tab leaves the split it was in. All the panes are kept in one
    /// place: the split's, unless open tabs meet a favorite, which keeps its own, so that no favorite is lost. They
    /// follow one another in reading order where the split was, or the favorite, so a split's first pane is where it
    /// shows in the sidebar.
    @discardableResult
    public mutating func split(_ tabID: UUID, beside targetID: UUID, at edge: SplitEdge) -> Bool {
        join(tabID, with: targetID) { $0.inserting(tabID, beside: targetID, at: edge) }
    }

    /// Shows `tabID` along `edge` of the whole split of `targetID`, or of `targetID` alone, as `split(_:beside:at:)` does.
    @discardableResult
    public mutating func split(_ tabID: UUID, alongside targetID: UUID, at edge: SplitEdge) -> Bool {
        join(tabID, with: targetID) { $0.inserting(tabID, at: edge) }
    }

    /// Puts `tabID` where `placing` says in the layout of `targetID`'s split, or of `targetID` alone.
    private mutating func join(_ tabID: UUID, with targetID: UUID, placing: (SplitNode) -> SplitNode?) -> Bool {
        guard tabID != targetID, let tab = tabs.first(where: { $0.id == tabID }), let target = tabs.first(where: { $0.id == targetID }),
              tab.spaceID == target.spaceID else { return false }
        let existing = split(containing: targetID)
        let alreadyIn = existing?.root.tabIDs.contains(tabID) == true
        guard alreadyIn || (existing?.tabIDs.count ?? 1) < TabSplit.maximumPanes else { return false }
        if !alreadyIn { removeFromSplit(tabID) }
        let base = alreadyIn ? existing.flatMap { $0.root.removing(tabID) } : (existing?.root ?? .pane(targetID))
        guard let root = base.flatMap(placing) else { return false }
        let place = target.place == .open ? tab.place : target.place
        let anchor = place == target.place ? Set(root.tabIDs).subtracting([tabID]) : [tabID]
        let following = entry(after: anchor, skipping: Set(root.tabIDs), in: place, spaceID: target.spaceID)
        for pane in root.tabIDs { _ = moveTab(pane, to: place, before: following) }
        if let index = splits.firstIndex(where: { $0.id == existing?.id }) { splits[index].root = root }
        else { splits.append(TabSplit(spaceID: target.spaceID, root: root)) }
        return true
    }

    /// The panes of the split in the sidebar's order.
    private func orderedPanes(of split: TabSplit) -> [UUID] {
        let panes = Set(split.tabIDs)
        return tabs.filter { panes.contains($0.id) }.map(\.id)
    }

    /// What follows the last of `tabIDs` in `place`, other than `skipped`: a tab or, among the pinned favorites, a group;
    /// `nil` when nothing does.
    private func entry(after tabIDs: Set<UUID>, skipping skipped: Set<UUID>, in place: TabPlace, spaceID: UUID) -> UUID? {
        let order: [UUID] = place == .list(group: nil)
            ? pinned(in: spaceID).map(\.id)
            : tabs.filter { $0.spaceID == spaceID && $0.place == place }.map(\.id)
        guard let last = order.lastIndex(where: tabIDs.contains) else { return nil }
        return order[(last + 1)...].first { !skipped.contains($0) }
    }

    /// Splits whose every pane moved to `spaceID`, under the identities `moved` gives them, follow them there.
    private mutating func carrySplits(_ moved: [UUID: UUID], to spaceID: UUID) {
        for index in splits.indices where splits[index].tabIDs.allSatisfy({ moved[$0] != nil }) {
            splits[index].root = splits[index].root.mapping { moved[$0] ?? $0 }
            splits[index].spaceID = spaceID
        }
        pruneSplits()
    }

    /// The tab leaves its split, which ends when one pane is left.
    public mutating func removeFromSplit(_ tabID: UUID) {
        guard let index = splits.firstIndex(where: { $0.root.tabIDs.contains(tabID) }) else { return }
        if let root = splits[index].root.removing(tabID), root.tabIDs.count > 1 { splits[index].root = root }
        else { splits.remove(at: index) }
    }

    /// Ends the split; its tabs stay open, one after the other.
    public mutating func separate(splitID: UUID) {
        splits.removeAll { $0.id == splitID }
    }

    public mutating func resizeSplit(id: UUID, divider: SplitDivider.Place, to boundary: Double) {
        guard let index = splits.firstIndex(where: { $0.id == id }) else { return }
        splits[index].root = splits[index].root.resizing(divider, to: boundary)
    }

    public mutating func equalizeSplit(id: UUID) {
        guard let index = splits.firstIndex(where: { $0.id == id }) else { return }
        splits[index].root = splits[index].root.equalized
    }

    /// A pane whose tab closed, or went to another space or place than its split's first pane, leaves its split; a split
    /// of one pane ends.
    private mutating func pruneSplits() {
        let records = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
        splits = splits.compactMap { split in
            let place = orderedPanes(of: split).first.flatMap { records[$0]?.place }
            var root: SplitNode? = split.root
            for id in split.root.tabIDs where records[id]?.spaceID != split.spaceID || records[id]?.place != place {
                root = root?.removing(id)
            }
            guard let root, root.tabIDs.count > 1 else { return nil }
            var kept = split
            kept.root = root
            return kept
        }
    }

    /// A favorite whose group has gone since comes back among the loose favorites.
    public mutating func restore(_ tab: BrowserTab) {
        guard spaces.contains(where: { $0.id == tab.spaceID }), !tabs.contains(where: { $0.id == tab.id }) else { return }
        var tab = tab
        if !isValid(tab.place, in: tab.spaceID) { tab.place = .list(group: nil) }
        keepingPinnedOrder(of: [tab.spaceID]) { $0.tabs.append(tab) }
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
              spaces.allSatisfy({ $0.groups.allSatisfy { Self.trimmed($0.name) == $0.name && ($0.icon.map { Self.trimmed($0) == $0 } ?? true) } }),
              tabs.allSatisfy({ spaceIDs.contains($0.spaceID) && NavigationInput.isTabURL($0.url) && isValid($0.place, in: $0.spaceID) }),
              tabs.allSatisfy({ $0.name.map { Self.trimmed($0) == $0 } ?? true }),
              tabs.allSatisfy({ ($0.pinnedURL != nil) == $0.isFavorite && ($0.pinnedURL.map(NavigationInput.isTabURL) ?? true) }),
              splitsAreValid
        else { throw SessionError.inconsistentData }
    }

    /// Each split holds two to four distinct tabs of its space, all in one place, and a tab is in one at most.
    private var splitsAreValid: Bool {
        let records = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
        let panes = splits.flatMap(\.tabIDs)
        return Set(splits.map(\.id)).count == splits.count && Set(panes).count == panes.count
            && splits.allSatisfy { split in
                let places = Set(split.tabIDs.compactMap { records[$0]?.place })
                return (2...TabSplit.maximumPanes).contains(split.tabIDs.count) && split.root.isValid && places.count == 1
                    && split.tabIDs.allSatisfy { records[$0]?.spaceID == split.spaceID }
            }
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
