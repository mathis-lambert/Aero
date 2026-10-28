import BrowserCore
import Foundation

/// A space's tabs in the order the sidebar shows them, with dragged tabs or a dragged group already where they
/// would land, so the page shows exactly what a drop does, from this space or another.
struct SidebarTabs {
    static let rowSpacing: CGFloat = 4

    struct Section {
        let place: TabPlace
        let tabs: [BrowserTab]
    }

    /// What the sidebar shows as one tab: a tab, or a split with its panes' tabs in reading order, which is also their
    /// order in the sidebar (docs/SPLIT_VIEW.md). It stands where its first tab is, and goes by that tab's identity.
    enum Entry: Identifiable {
        case tab(BrowserTab)
        case split(TabSplit, [BrowserTab])

        var id: UUID { tabs[0].id }

        var tabs: [BrowserTab] {
            switch self {
            case .tab(let tab): [tab]
            case .split(_, let panes): panes
            }
        }
    }

    /// An entry of the pinned list: a loose favorite or split, or a group with its tabs.
    enum Pinned: Identifiable {
        case entry(Entry)
        case group(TabGroup, [BrowserTab])

        var id: UUID {
            switch self {
            case .entry(let entry): entry.id
            case .group(let group, _): group.id
            }
        }
    }

    let grid: [BrowserTab]
    /// Groups and loose favorites, in any order.
    let pinned: [Pinned]
    let open: [BrowserTab]
    private let splits: [UUID: TabSplit]

    init(session: BrowserSession, space: BrowserSpace, drop: TabDrop?, pinnedDrop: PinnedDrop? = nil) {
        var session = session
        // Into a closed group the tabs would vanish, and the rows under the pointer would close up and retarget the
        // drop: they keep their place, as gaps, while the group lights up.
        let intoClosedGroup = if case .list(let group?) = drop?.destination.place {
            space.groups.first { $0.id == group }?.isCollapsed == true
        } else { false }
        if let drop, !intoClosedGroup {
            for id in drop.tabIDs where id != drop.destination.before {
                Self.arrive(id, in: space, session: &session)
                _ = session.move(id: id, to: drop.destination.place, before: drop.destination.before)
            }
        }
        for item in pinnedDrop?.items ?? [] where item.id != pinnedDrop?.before {
            switch item {
            case .tab(let id):
                Self.arrive(id, in: space, session: &session)
                _ = session.move(id: id, to: .list(group: nil), before: pinnedDrop?.before)
            case .group(let id):
                if space.groups.contains(where: { $0.id == id }) { session.moveGroup(id: id, before: pinnedDrop?.before) }
                else { _ = session.transferGroup(id: id, to: space.id, before: pinnedDrop?.before) }
            }
        }
        let own = session.tabs.filter { $0.spaceID == space.id }
        let tabs = Dictionary(grouping: own, by: \.place)
        let groups = Dictionary(uniqueKeysWithValues: (session.spaces.first { $0.id == space.id }?.groups ?? []).map { ($0.id, $0) })
        var splits: [UUID: TabSplit] = [:]
        for split in session.splits where split.spaceID == space.id {
            for id in split.tabIDs { splits[id] = split }
        }
        self.splits = splits
        grid = tabs[.grid, default: []]
        let loose = Self.entries(of: tabs[.list(group: nil), default: []], splits: splits)
        let entries = Dictionary(uniqueKeysWithValues: loose.map { ($0.id, $0) })
        pinned = session.pinned(in: space.id).compactMap { item in
            switch item {
            case .tab(let id): entries[id].map(Pinned.entry)
            case .group(let id): groups[id].map { .group($0, tabs[.list(group: id), default: []]) }
            }
        }
        open = tabs[.open, default: []]
    }

    /// The entries that show `tabs`, a run of one place: a split's tabs as one.
    func entries(of tabs: [BrowserTab]) -> [Entry] { Self.entries(of: tabs, splits: splits) }

    private static func entries(of tabs: [BrowserTab], splits: [UUID: TabSplit]) -> [Entry] {
        let records = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0) })
        var listed: Set<UUID> = []
        return tabs.compactMap { tab in
            guard let split = splits[tab.id] else { return .tab(tab) }
            guard listed.insert(split.id).inserted else { return nil }
            return .split(split, split.tabIDs.compactMap { records[$0] })
        }
    }

    /// The tabs, and every pane of a split among them: what goes when they are dragged.
    func carried(_ tabIDs: [UUID]) -> [UUID] {
        var seen: Set<UUID> = []
        return tabIDs.flatMap { splits[$0]?.tabIDs ?? [$0] }.filter { seen.insert($0).inserted }
    }

    var groups: [(group: TabGroup, tabs: [BrowserTab])] {
        pinned.compactMap { if case .group(let group, let tabs) = $0 { (group, tabs) } else { nil } }
    }

    var loose: [BrowserTab] {
        pinned.flatMap { item -> [BrowserTab] in if case .entry(let entry) = item { entry.tabs } else { [] } }
    }

    /// The runs a drop can land in; a closed group's rows are not on screen.
    var sections: [Section] {
        [Section(place: .grid, tabs: grid)]
            + groups.map { Section(place: .list(group: $0.group.id), tabs: $0.group.isCollapsed ? [] : $0.tabs) }
            + [Section(place: .list(group: nil), tabs: loose), Section(place: .open, tabs: open)]
    }

    /// Every tab top to bottom, a closed group's included: the order of numbered tabs.
    var ordered: [BrowserTab] { grid + pinned.flatMap(Self.tabs) + open }

    /// The rows on screen, top to bottom, groups' headers included: what a ⇧-click range runs through. A closed
    /// group's tabs are not part of it.
    var visibleOrder: [UUID] {
        let shown = pinned.flatMap { item -> [UUID] in
            switch item {
            case .entry(let entry): entry.tabs.map(\.id)
            case .group(let group, let tabs): [group.id] + (group.isCollapsed ? [] : tabs.map(\.id))
            }
        }
        return grid.map(\.id) + shown + open.map(\.id)
    }

    /// The picked groups and tabs in sidebar order, a picked group's tabs going with it; nil when no group is picked.
    func entries(of ids: Set<UUID>) -> [PinnedItem]? {
        let groups = Set(self.groups.map(\.group.id)).intersection(ids)
        guard !groups.isEmpty else { return nil }
        let carried = Set(self.groups.filter { groups.contains($0.group.id) }.flatMap { $0.tabs.map(\.id) })
        let order = grid.map(\.id) + pinned.flatMap { item -> [UUID] in
            switch item {
            case .entry(let entry): entry.tabs.map(\.id)
            case .group(let group, let members): [group.id] + members.map(\.id)
            }
        } + open.map(\.id)
        return order.filter { ids.contains($0) && !carried.contains($0) }.map { groups.contains($0) ? .group($0) : .tab($0) }
    }

    var frameTargets: Set<TabDropLayout.Target> {
        Set(sections.flatMap { section in
            [.section(section.place)] + section.tabs.map { .tab($0.id) }
        } + groups.map { .groupHeader($0.group.id) })
    }

    /// Changes whenever a tab or a group moves, so the move can animate.
    var order: [[UUID]] { [pinned.map(\.id)] + sections.map { $0.tabs.map(\.id) } }

    /// A tab from another space shows here as it will arrive, under its own identity for the preview, with the other
    /// panes of its split, as one.
    private static func arrive(_ id: UUID, in space: BrowserSpace, session: inout BrowserSession) {
        let panes = session.split(containing: id)?.tabIDs ?? [id]
        for pane in panes {
            guard let tab = session.tabs.first(where: { $0.id == pane }), tab.spaceID != space.id else { return }
            session.close(id: pane)
            session.restore(BrowserTab(id: pane, spaceID: space.id, url: tab.url, title: tab.title, name: tab.name, place: .open))
        }
        for (previous, pane) in zip(panes, panes.dropFirst()) { session.split(pane, beside: previous, at: .trailing) }
    }

    private static func tabs(_ item: Pinned) -> [BrowserTab] {
        switch item {
        case .entry(let entry): entry.tabs
        case .group(_, let tabs): tabs
        }
    }
}
