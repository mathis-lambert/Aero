@testable import Aero
import BrowserCore
import CoreGraphics
import Foundation
import Testing

// docs/BROWSING.md › Favorites and open tabs and docs/SHORTCUTS.md › Defaults. Written as failure modes first:
// 1. Numbered tabs skip a collapsed group's tabs, or count sections out of sidebar order.
// 2. A drag preview shows a different order than the drop makes, or closes up the rows under a pointer aiming at a
//    closed group.
// 3. A drop in the grid picks a slot from tiles moving aside, so a still pointer flips between slots.
// 4. A right-to-left grid counts its columns from the wrong edge.
// 5. A row's upper and lower halves, a group header, or the space below the open tabs target the wrong place.
// docs/BROWSING.md › Several tabs at once:
// 6. ⌘ forgets the shown tab, or a second ⌘ on a picked tab keeps it.
// 7. ⇧ starts from the wrong tab, runs one way only, or takes a closed group's hidden rows.
// 8. An action meant for one tab takes the selection, or one for the selection takes them out of sidebar order or
//    takes a closed tab.
// 9. Several dragged tabs land apart or reordered, a tab from another space does not show where it lands, or a
//    dragged tab's gap retargets the drop.
// 10. A drag resting on a side of the page names the wrong side in right-to-left.
// 12. In the pinned list, a tab cannot land before or after a group, or a group before or after a loose favorite.
// 13. Picked groups and tabs move out of sidebar order, a picked group's tab moves on its own, or tabs from the grid
//     and open tabs dragged with a group do not land in the pinned list beside it.
// 11. A dragged group lands at the wrong place among the groups, its gap retargets it, or one from another space
//     does not show; a tab resting on an open group, or a group on any, opens it.
// docs/SPLIT_VIEW.md › Sidebar:
// 14. A split takes several grid slots or rows, a drop lands between its panes, or dragging one pane, from this space or
//     another, leaves the others.

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
        let drop = TabDrop(tabIDs: [ids.open[1]], destination: TabDestination(place: .grid, before: ids.tiles[0]))
        let preview = SidebarTabs(session: ids.session, space: ids.space, drop: drop)
        #expect(preview.grid.map(\.id) == [ids.open[1]] + ids.tiles)
        #expect(preview.open.map(\.id) == [ids.open[0]])
        #expect(ids.tabs.open.count == 2, "The preview never changes the session")
        let closed = SidebarTabs(session: ids.session, space: ids.space,
                                 drop: TabDrop(tabIDs: [ids.open[1]], destination: TabDestination(place: .list(group: ids.tabs.groups[0].group.id), before: nil)))
        #expect(closed.open.map(\.id) == ids.open, "Into a closed group, the tab keeps its place until it opens")
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
        #expect(layout.destination(at: CGPoint(x: leading, y: 10), for: [ids.open[0]], in: tabs, current: nil) == TabDestination(place: .grid, before: ids.tiles[0]))
        #expect(layout.destination(at: CGPoint(x: second, y: 10), for: [ids.open[0]], in: tabs, current: nil) == TabDestination(place: .grid, before: nil),
                "Past the middle of the last tile, the drop goes after it")
        #expect(layout.destination(at: CGPoint(x: leading, y: 10), for: [ids.tiles[0]], in: tabs, current: nil) == TabDestination(place: .grid, before: ids.tiles[1]),
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
        #expect(layout.destination(at: CGPoint(x: 50, y: 205), for: [dragged], in: tabs, current: nil) == TabDestination(place: .open, before: ids.open[0]), "Upper half: before")
        #expect(layout.destination(at: CGPoint(x: 50, y: 230), for: [dragged], in: tabs, current: nil) == TabDestination(place: .open, before: ids.open[1]), "Lower half: after")
        #expect(layout.destination(at: CGPoint(x: 50, y: 110), for: [dragged], in: tabs, current: nil) == TabDestination(place: .list(group: group), before: nil), "A header takes it into its group")
        #expect(layout.destination(at: CGPoint(x: 50, y: 400), for: [dragged], in: tabs, current: nil) == TabDestination(place: .open, before: nil), "Below everything: the end of the open tabs")
        let current = TabDestination(place: .list(group: nil), before: nil)
        #expect(layout.destination(at: CGPoint(x: 50, y: 150), for: [ids.pinned], in: tabs, current: current) == current, "Over its own gap, a drag keeps its target")
    }

    @Test func commandClickPicksAlongTheShownTabAndDropsAPickedOne() {
        let ids = Arrangement()
        var selection = TabSelection()
        selection.toggle(ids.open[1], shown: ids.open[0])
        #expect(selection.ids == [ids.open[0], ids.open[1]], "The shown tab is part of the first pick")
        selection.toggle(ids.tiles[0], shown: ids.open[0])
        selection.toggle(ids.open[1], shown: ids.open[0])
        #expect(selection.ids == [ids.open[0], ids.tiles[0]])
        var fromNewTab = TabSelection()
        fromNewTab.toggle(ids.pinned, shown: nil)
        #expect(fromNewTab.ids == [ids.pinned], "New Tab is not a tab to pick")
    }

    @Test func shiftClickTakesTheVisibleRangeFromTheAnchor() {
        let ids = Arrangement()
        let order = ids.tabs.visibleOrder
        let group = ids.tabs.groups[0].group.id
        #expect(order == ids.tiles + [group, ids.pinned] + ids.open, "A closed group's header is on screen, its rows are not")
        var selection = TabSelection()
        selection.extend(to: ids.open[1], shown: ids.tiles[1], visible: order)
        #expect(selection.ids == [ids.tiles[1], group, ids.pinned, ids.open[0], ids.open[1]], "From the shown tab, across sections, taking the closed group")
        selection.extend(to: ids.tiles[0], shown: ids.tiles[1], visible: order)
        #expect(selection.ids == [ids.tiles[0], ids.tiles[1]], "The anchor stays: the range runs the other way")
        selection.toggle(ids.open[1], shown: ids.tiles[1])
        selection.extend(to: ids.pinned, shown: ids.tiles[1], visible: order)
        #expect(selection.ids == [ids.pinned, ids.open[0], ids.open[1]], "⌘ moves the anchor")
        var empty = TabSelection()
        empty.extend(to: ids.open[0], shown: nil, visible: order)
        #expect(empty.ids == [ids.open[0]], "With nothing shown, the range is the tab clicked")
    }

    @Test func actionsTakeTheSelectionOnlyFromOneOfItsTabs() {
        var ids = Arrangement()
        let order = ids.tabs.grid + ids.tabs.groups.flatMap(\.tabs) + ids.tabs.loose + ids.tabs.open
        var selection = TabSelection()
        selection.toggle(ids.tiles[0], shown: ids.open[1])
        selection.toggle(ids.grouped[0], shown: ids.open[1])
        #expect(selection.targets(for: ids.pinned, in: order.map(\.id)) == [ids.pinned], "A tab outside the selection acts alone")
        #expect(selection.targets(for: ids.open[1], in: order.map(\.id)) == [ids.tiles[0], ids.grouped[0], ids.open[1]],
                "In sidebar order, a closed group's tabs included")
        _ = ids.session.close(id: ids.grouped[0])
        _ = ids.session.close(id: ids.tiles[0])
        let remaining = ids.session.tabs.map(\.id)
        #expect(selection.targets(for: ids.open[1], in: remaining) == [ids.open[1]], "Closed tabs drop out, down to the tab itself")
    }

    @Test func severalDraggedTabsLandTogetherInOrder() {
        let ids = Arrangement()
        let drop = TabDrop(tabIDs: [ids.pinned, ids.open[1]], destination: TabDestination(place: .grid, before: ids.tiles[0]))
        let preview = SidebarTabs(session: ids.session, space: ids.space, drop: drop)
        #expect(preview.grid.map(\.id) == [ids.pinned, ids.open[1]] + ids.tiles)
        #expect(preview.loose.isEmpty && preview.open.map(\.id) == [ids.open[0]])
        let end = SidebarTabs(session: ids.session, space: ids.space,
                              drop: TabDrop(tabIDs: [ids.tiles[1], ids.pinned], destination: TabDestination(place: .open, before: nil)))
        #expect(end.open.map(\.id) == ids.open + [ids.tiles[1], ids.pinned], "At the end too")

        let layout = TabDropLayout()
        layout.frames[.tab(ids.open[0])] = CGRect(x: 0, y: 200, width: 200, height: 34)
        layout.frames[.tab(ids.open[1])] = CGRect(x: 0, y: 238, width: 200, height: 34)
        let current = TabDestination(place: .open, before: ids.open[0])
        #expect(layout.destination(at: CGPoint(x: 50, y: 250), for: [ids.pinned, ids.open[1]], in: ids.tabs, current: current) == current,
                "Over any dragged tab's gap, the drop keeps its target")
    }

    @Test func tabsFromAnotherSpaceShowWhereTheyLand() throws {
        var ids = Arrangement()
        let work = try ids.session.addSpace(name: "Work", profileID: ids.session.profiles[0].id, color: SpaceColor(0x2E9D5B))
        let opened = ids.session.open(URL(string: "https://example.test/work")!, in: work.id)
        let visiting = try #require(opened)
        let drop = TabDrop(tabIDs: [visiting.id], destination: TabDestination(place: .open, before: ids.open[1]))
        let preview = SidebarTabs(session: ids.session, space: ids.space, drop: drop)
        #expect(preview.open.map(\.id) == [ids.open[0], visiting.id, ids.open[1]])
        #expect(SidebarTabs(session: ids.session, space: work, drop: nil).open.map(\.id) == [visiting.id], "The preview never changes the session")
    }

    @Test func aSplitIsOneEntryThatMovesWhole() {
        var ids = Arrangement()
        ids.session.split(ids.tiles[1], beside: ids.tiles[0], at: .trailing)
        ids.session.split(ids.open[1], beside: ids.open[0], at: .bottom)
        let tabs = ids.tabs
        #expect(tabs.entries(of: tabs.grid).map(\.id) == [ids.tiles[0]], "Two favorites in a split are one tile")
        #expect(tabs.carried([ids.open[1]]) == ids.open, "Dragging one pane takes the split")

        let layout = TabDropLayout()
        layout.frames[.section(.grid)] = CGRect(x: 0, y: 0, width: 192, height: FavoritesGrid.tileHeight)
        let past = FavoritesGrid.tileWidth(in: 192) * 0.75
        #expect(layout.destination(at: CGPoint(x: past, y: 10), for: [ids.pinned], in: tabs, current: nil) == TabDestination(place: .grid, before: nil),
                "Past the middle of the split's tile, after the whole split")
        layout.frames[.tab(ids.open[0])] = CGRect(x: 0, y: 200, width: 200, height: 34)
        layout.frames[.section(.open)] = CGRect(x: 0, y: 200, width: 200, height: 34)
        #expect(layout.destination(at: CGPoint(x: 50, y: 230), for: [ids.pinned], in: tabs, current: nil) == TabDestination(place: .open, before: nil),
                "The lower half of a split's row drops after it, never between its panes")

        let drop = TabDrop(tabIDs: [ids.open[1]], destination: TabDestination(place: .grid, before: ids.tiles[0]))
        let preview = SidebarTabs(session: ids.session, space: ids.space, drop: drop)
        #expect(preview.grid.map(\.id) == ids.open + ids.tiles, "The split lands whole, in its order")
        #expect(preview.entries(of: preview.grid).count == 2)
    }

    @Test func aSplitFromAnotherSpaceShowsWholeWhereItLands() throws {
        var ids = Arrangement()
        let work = try ids.session.addSpace(name: "Work", profileID: ids.session.profiles[0].id, color: SpaceColor(0x2E9D5B))
        let panes = (0..<2).compactMap { ids.session.open(URL(string: "https://example.test/work/\($0)")!, in: work.id)?.id }
        ids.session.split(panes[1], beside: panes[0], at: .trailing)
        let drop = TabDrop(tabIDs: [panes[1]], destination: TabDestination(place: .open, before: nil))
        let preview = SidebarTabs(session: ids.session, space: ids.space, drop: drop)
        let arrived = preview.entries(of: preview.open).last
        #expect(arrived?.tabs.map(\.id) == panes, "Both panes arrive, as one split")
    }

    @Test(arguments: [false, true])
    func aDragRestsOnTheSideItIsOn(rightToLeft: Bool) {
        let layout = TabDropLayout()
        layout.rightToLeft = rightToLeft
        let width: CGFloat = 212
        #expect(layout.edge(at: CGPoint(x: 4, y: 100), width: width) == (rightToLeft ? .trailing : .leading))
        #expect(layout.edge(at: CGPoint(x: width - 4, y: 100), width: width) == (rightToLeft ? .leading : .trailing))
        #expect(layout.edge(at: CGPoint(x: width / 2, y: 100), width: width) == nil)
        #expect(layout.edge(at: CGPoint(x: 4, y: 100), width: 0) == nil, "Before the page has a width")
    }

    @Test func aDraggedGroupLandsAmongTheGroups() throws {
        var ids = Arrangement()
        let reading = ids.tabs.groups[0].group
        let added = ids.session.addGroup(named: "Later", in: ids.space.id)
        let later = try #require(added)
        let layout = TabDropLayout()
        layout.frames[.section(.list(group: reading.id))] = CGRect(x: 0, y: 100, width: 200, height: 34)
        layout.frames[.tab(ids.pinned)] = CGRect(x: 0, y: 138, width: 200, height: 34)
        layout.frames[.section(.list(group: later.id))] = CGRect(x: 0, y: 176, width: 200, height: 34)
        let dragged: [PinnedItem] = [.group(later.id)]
        #expect(layout.pinnedDestination(at: CGPoint(x: 50, y: 110), for: dragged, in: ids.tabs, current: nil) == PinnedDrop(items: dragged, before: reading.id),
                "Above the middle of a group: before it")
        #expect(layout.pinnedDestination(at: CGPoint(x: 50, y: 160), for: dragged, in: ids.tabs, current: nil) == PinnedDrop(items: dragged, before: nil),
                "Below the middle of the last other entry: last")
        let current = PinnedDrop(items: dragged, before: reading.id)
        #expect(layout.pinnedDestination(at: CGPoint(x: 50, y: 190), for: dragged, in: ids.tabs, current: current) == current, "Over its own gap, it keeps its target")

        let preview = SidebarTabs(session: ids.session, space: ids.space, drop: nil, pinnedDrop: current)
        #expect(preview.pinned.map(\.id) == [later.id, reading.id, ids.pinned])
        #expect(preview.groups[1].tabs.map(\.id) == ids.grouped, "Its tabs move with it")
        #expect(ids.tabs.groups.map(\.group.id) == [reading.id, later.id], "The preview never changes the session")

        let work = try ids.session.addSpace(name: "Work", profileID: ids.session.profiles[0].id, color: SpaceColor(0x2E9D5B))
        let other = ids.session.addGroup(named: "Visiting", in: work.id)
        let visiting = try #require(other)
        let arriving = SidebarTabs(session: ids.session, space: ids.space, drop: nil, pinnedDrop: PinnedDrop(items: [.group(visiting.id)], before: later.id))
        #expect(arriving.pinned.map(\.id) == [reading.id, ids.pinned, visiting.id, later.id], "A group from another space shows where it lands")
    }

    @Test func onlyAClosedGroupOpensUnderADraggedTab() throws {
        var ids = Arrangement()
        let reading = ids.tabs.groups[0].group
        let added = ids.session.addGroup(named: "Open", in: ids.space.id)
        let open = try #require(added)
        let layout = TabDropLayout()
        layout.frames[.groupHeader(reading.id)] = CGRect(x: 0, y: 100, width: 200, height: 34)
        layout.frames[.groupHeader(open.id)] = CGRect(x: 0, y: 138, width: 200, height: 34)
        #expect(layout.closedGroup(at: CGPoint(x: 50, y: 110), in: ids.tabs) == reading.id)
        #expect(layout.closedGroup(at: CGPoint(x: 50, y: 150), in: ids.tabs) == nil, "An open group has nothing to open")
        #expect(layout.closedGroup(at: CGPoint(x: 50, y: 300), in: ids.tabs) == nil)
    }

    @Test func tabsAndGroupsLandOnEitherSideOfEachOther() {
        let ids = Arrangement()
        let tabs = ids.tabs
        let group = tabs.groups[0].group.id
        #expect(tabs.pinned.map(\.id) == [group, ids.pinned], "The fixture's group comes first")
        let layout = TabDropLayout()
        layout.frames[.groupHeader(group)] = CGRect(x: 0, y: 100, width: 200, height: 32)
        layout.frames[.section(.list(group: group))] = CGRect(x: 0, y: 100, width: 200, height: 32)
        layout.frames[.tab(ids.pinned)] = CGRect(x: 0, y: 136, width: 200, height: 34)
        let dragged = [ids.open[0]]
        #expect(layout.destination(at: CGPoint(x: 50, y: 103), for: dragged, in: tabs, current: nil) == TabDestination(place: .list(group: nil), before: group),
                "The top of a header drops before the group")
        #expect(layout.destination(at: CGPoint(x: 50, y: 129), for: dragged, in: tabs, current: nil) == TabDestination(place: .list(group: nil), before: ids.pinned),
                "The bottom of a closed group's header drops after it")
        #expect(layout.destination(at: CGPoint(x: 50, y: 116), for: dragged, in: tabs, current: nil) == TabDestination(place: .list(group: group), before: nil))
        #expect(layout.destination(at: CGPoint(x: 50, y: 140), for: dragged, in: tabs, current: nil) == TabDestination(place: .list(group: nil), before: ids.pinned))
        let dropped = SidebarTabs(session: ids.session, space: ids.space,
                                  drop: TabDrop(tabIDs: dragged, destination: TabDestination(place: .list(group: nil), before: group)))
        #expect(dropped.pinned.map(\.id) == [ids.open[0], group, ids.pinned], "The preview puts it before the group")

        #expect(layout.pinnedDestination(at: CGPoint(x: 50, y: 165), for: [.group(group)], in: tabs, current: nil) == PinnedDrop(items: [.group(group)], before: nil),
                "Past a loose favorite's middle, the group goes after it")
        let moved = SidebarTabs(session: ids.session, space: ids.space, drop: nil, pinnedDrop: PinnedDrop(items: [.group(group)], before: nil))
        #expect(moved.pinned.map(\.id) == [ids.pinned, group])
        #expect(moved.visibleOrder == ids.tiles + [ids.pinned, group] + ids.open, "A closed group's tabs are off screen wherever it is")
    }

    @Test func pickedGroupsAndTabsMoveTogetherInOrder() throws {
        var ids = Arrangement()
        let reading = ids.tabs.groups[0].group.id
        let added = ids.session.addGroup(named: "Later", in: ids.space.id)
        let later = try #require(added).id
        #expect(ids.tabs.entries(of: [ids.open[0], ids.pinned]) == nil, "Without a group, tabs act alone")
        let entries = try #require(ids.tabs.entries(of: [ids.open[1], later, ids.grouped[0], reading, ids.tiles[0]]))
        #expect(entries == [.tab(ids.tiles[0]), .group(reading), .group(later), .tab(ids.open[1])],
                "In sidebar order; a picked group's tab goes with its group")

        let drop = PinnedDrop(items: entries, before: ids.pinned)
        let preview = SidebarTabs(session: ids.session, space: ids.space, drop: nil, pinnedDrop: drop)
        #expect(preview.pinned.map(\.id) == [ids.tiles[0], reading, later, ids.open[1], ids.pinned], "All of them before the target, in order")
        #expect(preview.grid.map(\.id) == [ids.tiles[1]] && preview.open.map(\.id) == [ids.open[0]])
        #expect(preview.groups[0].tabs.map(\.id) == ids.grouped, "Groups keep their tabs")
    }
}
