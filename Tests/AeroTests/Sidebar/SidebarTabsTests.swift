@testable import Aero
import BrowserCore
import CoreGraphics
import Foundation
import Testing

// docs/BROWSING.md › Favorites and open tabs and docs/SHORTCUTS.md › Defaults. Written as failure modes first:
// 1. Numbered tabs skip a collapsed group's tabs, or count sections out of sidebar order.
// 2. A drag preview shows a different order than the drop makes.
// 3. A drop in the grid picks a slot from tiles moving aside, so a still pointer flips between slots.
// 4. A right-to-left grid counts its columns from the wrong edge.
// 5. A row's upper and lower halves, a group header, or the space below the open tabs target the wrong place.

@MainActor
struct SidebarTabsTests {
    /// Two favorites, a collapsed group of two, a pinned tab and two open tabs, added out of order.
    private struct Arrangement {
        var session = BrowserSession(profileName: "Personal")
        var tiles: [UUID] = [], grouped: [UUID] = [], pinned = UUID(), open: [UUID] = []
        var space: BrowserSpace { session.spaces[0] }
        var tabs: SidebarTabs { SidebarTabs(session: session, space: space, drop: nil) }

        init() {
            let group = session.addGroup(named: "Reading", in: session.spaces[0].id)!
            func add(_ place: TabPlace) -> UUID {
                let tab = session.open(URL(string: "https://example.test/")!, in: session.spaces[0].id)!
                _ = session.move(id: tab.id, to: place, before: nil)
                return tab.id
            }
            let firstOpen = add(.open), firstTile = add(.grid), firstGrouped = add(.list(group: group.id))
            pinned = add(.list(group: nil))
            let secondTile = add(.grid), secondGrouped = add(.list(group: group.id)), secondOpen = add(.open)
            session.setGroupCollapsed(id: group.id, true)
            tiles = [firstTile, secondTile]
            grouped = [firstGrouped, secondGrouped]
            open = [firstOpen, secondOpen]
        }
    }

    @Test func tabsFollowSidebarOrderIncludingCollapsedGroups() {
        let ids = Arrangement()
        let tabs = ids.tabs
        let ordered = tabs.grid + tabs.groups.flatMap(\.tabs) + tabs.loose + tabs.open
        #expect(ordered.map(\.id) == ids.tiles + ids.grouped + [ids.pinned] + ids.open, "Favorites first, then groups, pinned and open tabs")
        #expect(tabs.sections.map(\.tabs.count) == [2, 0, 1, 2], "A collapsed group shows no rows, yet keeps its numbers")
    }

    @Test func aDragPreviewShowsWhereTheDropLands() {
        let ids = Arrangement()
        let drop = TabDrop(tabID: ids.open[1], destination: TabDestination(place: .grid, before: ids.tiles[0]))
        let preview = SidebarTabs(session: ids.session, space: ids.space, drop: drop)
        #expect(preview.grid.map(\.id) == [ids.open[1]] + ids.tiles)
        #expect(preview.open.map(\.id) == [ids.open[0]])
        #expect(ids.tabs.open.count == 2, "The preview never changes the session")
    }

    @Test(arguments: [false, true])
    func gridSlotsComeFromGeometry(rightToLeft: Bool) {
        let ids = Arrangement()
        let tabs = ids.tabs
        let layout = TabDropLayout()
        layout.rightToLeft = rightToLeft
        let grid = CGRect(x: 0, y: 0, width: 192, height: FavoritesGrid.tileHeight)
        layout.frames[.section(.grid)] = grid
        let width = FavoritesGrid.tileWidth(in: grid.width)
        // The first column's leading edge, from whichever side the grid starts.
        let leading = rightToLeft ? grid.maxX - 2 : grid.minX + 2
        let second = rightToLeft ? grid.maxX - width - FavoritesGrid.spacing - width * 0.75 : width + FavoritesGrid.spacing + width * 0.75
        #expect(layout.destination(at: CGPoint(x: leading, y: 10), for: ids.open[0], in: tabs, current: nil) == TabDestination(place: .grid, before: ids.tiles[0]))
        #expect(layout.destination(at: CGPoint(x: second, y: 10), for: ids.open[0], in: tabs, current: nil) == TabDestination(place: .grid, before: nil),
                "Past the middle of the last tile, the drop goes after it")
        #expect(layout.destination(at: CGPoint(x: leading, y: 10), for: ids.tiles[0], in: tabs, current: nil) == TabDestination(place: .grid, before: ids.tiles[1]),
                "The dragged tile leaves its slot to the others")
    }

    @Test func rowsHeadersAndTheSpaceBelowTargetTheirPlace() {
        let ids = Arrangement()
        let tabs = ids.tabs
        let group = tabs.groups[0].group.id
        let layout = TabDropLayout()
        layout.frames[.tab(ids.open[0])] = CGRect(x: 0, y: 200, width: 200, height: 34)
        layout.frames[.tab(ids.open[1])] = CGRect(x: 0, y: 238, width: 200, height: 34)
        layout.frames[.tab(ids.pinned)] = CGRect(x: 0, y: 140, width: 200, height: 34)
        layout.frames[.groupHeader(group)] = CGRect(x: 0, y: 100, width: 200, height: 34)
        layout.frames[.section(.open)] = CGRect(x: 0, y: 200, width: 200, height: 72)
        let dragged = ids.tiles[0]
        #expect(layout.destination(at: CGPoint(x: 50, y: 205), for: dragged, in: tabs, current: nil) == TabDestination(place: .open, before: ids.open[0]), "Upper half: before")
        #expect(layout.destination(at: CGPoint(x: 50, y: 230), for: dragged, in: tabs, current: nil) == TabDestination(place: .open, before: ids.open[1]), "Lower half: after")
        #expect(layout.destination(at: CGPoint(x: 50, y: 110), for: dragged, in: tabs, current: nil) == TabDestination(place: .list(group: group), before: nil), "A header takes it into its group")
        #expect(layout.destination(at: CGPoint(x: 50, y: 400), for: dragged, in: tabs, current: nil) == TabDestination(place: .open, before: nil), "Below everything: the end of the open tabs")
        let current = TabDestination(place: .list(group: nil), before: nil)
        #expect(layout.destination(at: CGPoint(x: 50, y: 150), for: ids.pinned, in: tabs, current: current) == current, "Over its own gap, a drag keeps its target")
    }
}
