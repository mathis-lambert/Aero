import BrowserCore
import Foundation

/// A space's tabs in the order the sidebar shows them, with a dragged tab already where it
/// would land, so the page shows exactly what a drop does.
struct SidebarTabs {
    static let rowSpacing: CGFloat = 4

    struct Section {
        let place: TabPlace
        let tabs: [BrowserTab]
    }

    let grid: [BrowserTab]
    let groups: [(group: TabGroup, tabs: [BrowserTab])]
    let loose: [BrowserTab]
    let open: [BrowserTab]

    init(session: BrowserSession, space: BrowserSpace, drop: TabDrop?) {
        var session = session
        if let drop { _ = session.move(id: drop.tabID, to: drop.destination.place, before: drop.destination.before) }
        let tabs = Dictionary(grouping: session.tabs.lazy.filter { $0.spaceID == space.id }, by: \.place)
        grid = tabs[.grid, default: []]
        groups = space.groups.map { group in (group, tabs[.list(group: group.id), default: []]) }
        loose = tabs[.list(group: nil), default: []]
        open = tabs[.open, default: []]
    }

    /// The runs a drop can land in, top to bottom; a closed group's rows are not on screen.
    var sections: [Section] {
        [Section(place: .grid, tabs: grid)]
            + groups.map { Section(place: .list(group: $0.group.id), tabs: $0.group.isCollapsed ? [] : $0.tabs) }
            + [Section(place: .list(group: nil), tabs: loose), Section(place: .open, tabs: open)]
    }

    var frameTargets: Set<TabDropLayout.Target> {
        Set(sections.flatMap { section in
            [.section(section.place)] + section.tabs.map { .tab($0.id) }
        } + groups.map { .groupHeader($0.group.id) })
    }

    /// Changes whenever a tab moves, so the move can animate.
    var order: [[UUID]] { sections.map { $0.tabs.map(\.id) } }
}
