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

    /// An entry of the pinned list: a loose favorite, or a group with its tabs.
    enum Pinned: Identifiable {
        case tab(BrowserTab)
        case group(TabGroup, [BrowserTab])

        var id: UUID {
            switch self {
            case .tab(let tab): tab.id
            case .group(let group, _): group.id
            }
        }
    }

    let grid: [BrowserTab]
    /// Groups and loose favorites, in any order.
    let pinned: [Pinned]
    let open: [BrowserTab]

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
        let records = Dictionary(uniqueKeysWithValues: own.map { ($0.id, $0) })
        let groups = Dictionary(uniqueKeysWithValues: (session.spaces.first { $0.id == space.id }?.groups ?? []).map { ($0.id, $0) })
        grid = tabs[.grid, default: []]
        pinned = session.pinned(in: space.id).compactMap { item in
            switch item {
            case .tab(let id): records[id].map(Pinned.tab)
            case .group(let id): groups[id].map { .group($0, tabs[.list(group: id), default: []]) }
            }
        }
        open = tabs[.open, default: []]
    }

    var groups: [(group: TabGroup, tabs: [BrowserTab])] {
        pinned.compactMap { if case .group(let group, let tabs) = $0 { (group, tabs) } else { nil } }
    }

    var loose: [BrowserTab] {
        pinned.compactMap { if case .tab(let tab) = $0 { tab } else { nil } }
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
            case .tab(let tab): [tab.id]
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
            if case .group(let group, let members) = item { [group.id] + members.map(\.id) } else { [item.id] }
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

    /// A tab from another space shows here as it will arrive, under its own identity for the preview.
    private static func arrive(_ id: UUID, in space: BrowserSpace, session: inout BrowserSession) {
        guard let tab = session.tabs.first(where: { $0.id == id }), tab.spaceID != space.id else { return }
        session.close(id: id)
        session.restore(BrowserTab(id: id, spaceID: space.id, url: tab.url, title: tab.title, name: tab.name, place: .open))
    }

    private static func tabs(_ item: Pinned) -> [BrowserTab] {
        switch item {
        case .tab(let tab): [tab]
        case .group(_, let tabs): tabs
        }
    }
}
