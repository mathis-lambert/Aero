import CoreGraphics
import Foundation
import Testing
@testable import BrowserCore

// docs/SPLIT_VIEW.md. Written as failure modes first:
// 1. A split holds a fifth pane, a tab twice, tabs of two places or spaces, or a single pane.
// 2. Closing a pane's tab leaves its split naming a tab it no longer shows.
// 8. Pinning, moving or transferring one pane leaves the others behind, or scatters the split among the favorites.
// 3. A pane beside another in the same direction nests a stack instead of sharing the row equally; removing a pane
//    leaves a hole, or a stack of one part, or a stack inside one of its own axis.
// 4. A divider is dragged so far that a pane disappears, moves parts it does not separate, or keeps a boundary that is
//    not a number.
// 5. Frames overlap, leave no gap between panes, or do not fill the area.
// 6. The stored layout reads back different, or a corrupt one is accepted.
// 9. Moving a pane to another's side leaves the layout malformed or loses a pane.
// 10. A pane asked for at the end of the page goes beside the focused pane instead, wherever it is.
// 7. A split's tabs are scattered in the sidebar's order, or out of reading order, so shortcuts jump around it.

private func session(tabs count: Int) -> (BrowserSession, [UUID]) {
    var session = BrowserSession(profileName: "Personal")
    let spaceID = session.spaces[0].id
    let ids = (0..<count).map { session.open(URL(string: "https://example.com/\($0)")!, in: spaceID)!.id }
    return (session, ids)
}

@Test func splitsHoldTwoToFourOpenTabsOfOneSpace() throws {
    var (session, ids) = session(tabs: 6)
    let besideItself = session.split(ids[0], beside: ids[0], at: .trailing)
    #expect(!besideItself, "A tab cannot be beside itself")
    let second = session.split(ids[1], beside: ids[0], at: .trailing)
    let third = session.split(ids[2], beside: ids[1], at: .bottom)
    let fourth = session.split(ids[3], beside: ids[0], at: .bottom)
    let fifth = session.split(ids[4], beside: ids[0], at: .top)
    #expect(second && third && fourth)
    #expect(!fifth, "No fifth pane")
    #expect(session.splits.count == 1 && session.splits[0].tabIDs.count == 4)
    try session.validate()

    _ = session.move(id: ids[5], to: .grid, before: nil)
    let favorite = session.split(ids[4], beside: ids[5], at: .trailing)
    #expect(favorite)
    #expect(session.tabs.first { $0.id == ids[4] }?.place == .grid, "A tab joining a favorite's split becomes a favorite too")
    try session.validate()
    _ = session.move(id: ids[0], to: .list(group: nil), before: nil)
    session.split(ids[0], beside: ids[1], at: .leading)
    #expect(session.splits.first { $0.tabIDs.contains(ids[0]) }?.tabIDs.allSatisfy { id in
        session.tabs.first { $0.id == id }?.place == .list(group: nil)
    } == true, "Open tabs meeting a favorite join it among the favorites: none is lost")
    try session.validate()

    let other = try session.addSpace(name: "Work", profileID: session.profiles[0].id, color: .initial)
    let opened = session.open(URL(string: "https://example.org")!, in: other.id)
    let elsewhere = try #require(opened)
    let acrossSpaces = session.split(elsewhere.id, beside: ids[4], at: .trailing)
    #expect(!acrossSpaces, "Panes share a space")
}

@Test func aPaneThatGoesLeavesItsSplit() throws {
    var (session, ids) = session(tabs: 4)
    session.split(ids[1], beside: ids[0], at: .trailing)
    session.split(ids[2], beside: ids[1], at: .trailing)
    session.close(id: ids[1])
    #expect(session.splits[0].tabIDs == [ids[0], ids[2]], "The closed pane's neighbor takes its place")
    session.close(id: ids[2])
    #expect(session.splits.isEmpty, "A split of one pane ends")
    try session.validate()
}

@Test func aSplitMovesAsOneTab() throws {
    var (session, ids) = session(tabs: 5)
    let spaceID = session.spaces[0].id
    _ = session.move(id: ids[4], to: .grid, before: nil)
    session.split(ids[2], beside: ids[0], at: .trailing)
    session.split(ids[1], beside: ids[2], at: .bottom)
    let layout = session.splits[0].root

    let pinned = session.move(id: ids[2], to: .grid, before: ids[4])
    #expect(pinned)
    #expect(session.tabs.filter { $0.place == .grid }.map(\.id) == [ids[0], ids[2], ids[1], ids[4]],
            "Every pane, in order, before the target")
    #expect(session.splits.first?.root == layout, "The layout is kept")
    let ontoItself = session.move(id: ids[0], to: .list(group: nil), before: ids[1])
    #expect(!ontoItself, "A split never goes before its own pane")

    _ = session.move(id: ids[1], to: .list(group: nil), before: nil)
    #expect(session.pinned(in: spaceID).map(\.id) == [ids[0], ids[2], ids[1]], "The pinned list keeps it together")
    try session.validate()

    let work = try session.addSpace(name: "Work", profileID: session.profiles[0].id, color: .initial)
    _ = session.transfer(id: ids[2], to: work.id)
    #expect(session.splits.first?.spaceID == work.id && session.splits.first?.root == layout, "Its split goes along")
    #expect(session.tabs.filter { $0.spaceID == work.id }.count == 3)
    try session.validate()

    let other = try session.addProfile(name: "Other")
    try session.editSpace(id: work.id, name: "Work", profileID: other.id, color: .initial, emoji: nil)
    let renewed = session.tabs.filter { $0.spaceID == work.id }.map(\.id)
    #expect(Set(session.splits.first?.tabIDs ?? []) == Set(renewed), "A new identity keeps the split")
    try session.validate()
}

@Test func aSplitsTabsStayTogetherInTheSidebarsOrder() {
    var (session, ids) = session(tabs: 4)
    session.split(ids[3], beside: ids[0], at: .trailing)
    #expect(session.tabs.map(\.id) == [ids[0], ids[3], ids[1], ids[2]])
    session.split(ids[2], beside: ids[3], at: .bottom)
    #expect(session.tabs.map(\.id) == [ids[0], ids[3], ids[2], ids[1]])
    session.split(ids[1], beside: ids[0], at: .leading)
    #expect(session.tabs.map(\.id) == [ids[1], ids[0], ids[3], ids[2]], "In reading order, the first pane leads")
}

@Test func aTabMovesWithinItsSplitOrToAnother() throws {
    var (session, ids) = session(tabs: 4)
    session.split(ids[1], beside: ids[0], at: .trailing)
    let within = session.split(ids[0], beside: ids[1], at: .trailing)
    #expect(within, "Moving within a split is allowed")
    #expect(session.splits[0].tabIDs == [ids[1], ids[0]])
    session.split(ids[3], beside: ids[2], at: .trailing)
    let across = session.split(ids[0], beside: ids[2], at: .bottom)
    #expect(across)
    #expect(session.splits.count == 1, "The split it left, down to one pane, ended")
    #expect(Set(session.splits[0].tabIDs) == [ids[0], ids[2], ids[3]])
    try session.validate()
}

private func row(_ ids: UUID...) -> SplitNode {
    .stack(.horizontal, ids.map { SplitPart(node: .pane($0), share: 1 / Double(ids.count)) })
}

@Test func panesInOneDirectionShareOneStackEqually() {
    let a = UUID(), b = UUID(), c = UUID(), d = UUID()
    let two = SplitNode.pane(a).inserting(b, beside: a, at: .trailing)!
    #expect(two == row(a, b))
    #expect(two.inserting(c, beside: a, at: .trailing) == row(a, c, b), "Beside, in the same row: thirds")
    let column = two.inserting(c, beside: b, at: .bottom)!
    #expect(column == .stack(.horizontal, [SplitPart(node: .pane(a), share: 0.5),
                                           SplitPart(node: .stack(.vertical, [SplitPart(node: .pane(b), share: 0.5), SplitPart(node: .pane(c), share: 0.5)]), share: 0.5)]))
    #expect(column.inserting(d, beside: c, at: .bottom)?.tabIDs == [a, b, c, d])
    #expect(column.inserting(d, beside: UUID(), at: .top) == nil, "No target, no change")
    #expect(column.isValid)
}

@Test func aPaneAtTheEndGoesAfterTheWholeLayout() throws {
    let a = UUID(), b = UUID(), c = UUID()
    #expect(SplitNode.pane(a).inserting(b, at: .trailing) == row(a, b))
    #expect(row(a, b).inserting(c, at: .trailing) == row(a, b, c), "The row's last part, in thirds")
    let column = SplitNode.stack(.vertical, [SplitPart(node: .pane(a), share: 0.5), SplitPart(node: .pane(b), share: 0.5)])
    #expect(column.inserting(c, at: .trailing) == .stack(.horizontal, [SplitPart(node: column, share: 0.5), SplitPart(node: .pane(c), share: 0.5)]),
            "Across a column, beside all of it")

    var (session, ids) = session(tabs: 3)
    session.split(ids[1], beside: ids[0], at: .trailing)
    let atEnd = session.split(ids[2], alongside: ids[0], at: .trailing)
    #expect(atEnd)
    #expect(session.splits.first?.root == row(ids[0], ids[1], ids[2]), "From the leading pane too, at the very end")
    try session.validate()
}

@Test func removingAPaneGivesItsShareToTheOthers() {
    let a = UUID(), b = UUID(), c = UUID()
    let three = row(a, b, c).resizing(SplitDivider.Place(path: [], index: 0), to: 0.5)
    let two = three.removing(a)
    #expect(two?.tabIDs == [b, c])
    // a 1/2, b 1/6, c 1/3: without a, b and c keep their proportion.
    if case .stack(_, let parts)? = two { #expect(abs(parts[0].share - 1.0 / 3) < 0.000_001 && abs(parts[1].share - 2.0 / 3) < 0.000_001) }
    #expect(SplitNode.pane(a).removing(a) == nil)
    #expect(row(a, b).removing(b) == .pane(a), "A stack of one part is that part")

    // a | (b over c): without b, c joins the row, never a stack of one inside it.
    let nested = row(a, b).inserting(c, beside: b, at: .bottom)!
    #expect(nested.removing(b) == row(a, c))
    // (a | b) over c, then c goes, and the row is the root again.
    let flattened = SplitNode.stack(.vertical, [SplitPart(node: row(a, b), share: 0.5), SplitPart(node: .pane(c), share: 0.5)]).removing(c)
    #expect(flattened == row(a, b))

    // a | (b over (c | d)), c at the minimum of its row: flattened into the root, it would fall below it.
    let d = UUID()
    let squeezed = row(c, d).resizing(SplitDivider.Place(path: [], index: 0), to: 0)
    let deep = SplitNode.stack(.horizontal, [SplitPart(node: .pane(a), share: 0.5),
                                             SplitPart(node: .stack(.vertical, [SplitPart(node: .pane(b), share: 0.5), SplitPart(node: squeezed, share: 0.5)]), share: 0.5)])
    let withoutB = deep.removing(b)
    #expect(withoutB == row(a, c, d) && withoutB?.isValid == true, "Shared equally rather than squeezed out")
}

@Test func dividersStopBeforeAPaneDisappears() {
    let a = UUID(), b = UUID(), c = UUID()
    let three = row(a, b, c)
    let pushed = three.resizing(SplitDivider.Place(path: [], index: 1), to: 0.99)
    guard case .stack(_, let parts) = pushed else { Issue.record("A stack stays one"); return }
    #expect(abs(parts[0].share - 1.0 / 3) < 0.000_001, "Only the parts beside the divider move")
    #expect(abs(parts[2].share - SplitNode.minimumShare) < 0.000_001)
    #expect(pushed.isValid)
    #expect(three.resizing(SplitDivider.Place(path: [], index: 0), to: .nan) == three, "A boundary that is not a number is ignored")
    #expect(three.resizing(SplitDivider.Place(path: [], index: 2), to: 0.5) == three, "No divider after the last part")
    #expect(pushed.equalized == three)
}

@Test func framesTileTheAreaWithGaps() {
    let a = UUID(), b = UUID(), c = UUID()
    let root = SplitNode.pane(a).inserting(b, beside: a, at: .trailing)!.inserting(c, beside: b, at: .bottom)!
    let area = CGRect(x: 0, y: 0, width: 1006, height: 806)
    let frames = root.frames(in: area, gap: 6)
    #expect(frames[a] == CGRect(x: 0, y: 0, width: 500, height: 806))
    #expect(frames[b] == CGRect(x: 506, y: 0, width: 500, height: 400))
    #expect(frames[c] == CGRect(x: 506, y: 406, width: 500, height: 400))
    let thirds = row(a, b, c).frames(in: CGRect(x: 0, y: 0, width: 1012, height: 100), gap: 6)
    #expect(thirds[c]?.maxX == 1012 && thirds[b]?.minX == 339, "Thirds fill the row to the point")
    let dividers = root.dividers(in: area, gap: 6)
    #expect(dividers.map(\.line) == [CGRect(x: 500, y: 0, width: 6, height: 806), CGRect(x: 506, y: 400, width: 500, height: 6)])
    #expect(dividers.map(\.place) == [SplitDivider.Place(path: [], index: 0), SplitDivider.Place(path: [1], index: 0)])
    #expect(abs(dividers[0].boundary(at: CGPoint(x: 503, y: 10), gap: 6) - 0.5) < 0.001, "The divider's center is its boundary")
}

@Test func movingAPaneToAnotherSideKeepsEveryPane() throws {
    var (session, ids) = session(tabs: 3)
    session.split(ids[1], beside: ids[0], at: .trailing)
    session.split(ids[2], beside: ids[1], at: .trailing)
    let moved = session.split(ids[0], beside: ids[2], at: .bottom)
    #expect(moved)
    let root = try #require(session.splits.first?.root)
    #expect(Set(root.tabIDs) == Set(ids) && root.isValid)
    #expect(root == .stack(.horizontal, [SplitPart(node: .pane(ids[1]), share: 0.5),
                                         SplitPart(node: .stack(.vertical, [SplitPart(node: .pane(ids[2]), share: 0.5), SplitPart(node: .pane(ids[0]), share: 0.5)]), share: 0.5)]))
    try session.validate()
}

@Test func theLayoutReadsBackAsWritten() throws {
    let a = UUID(), b = UUID(), c = UUID()
    let root = SplitNode.pane(a).inserting(b, beside: a, at: .top)!.inserting(c, beside: a, at: .leading)!
        .resizing(SplitDivider.Place(path: [], index: 0), to: 0.3)
    let data = try JSONEncoder().encode(root)
    #expect(try JSONDecoder().decode(SplitNode.self, from: data) == root)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(SplitNode.self, from: Data(#"{"axis":"diagonal","parts":[]}"#.utf8)) }
}

@Test func aCorruptSplitFailsValidation() throws {
    let (base, ids) = session(tabs: 3)
    let spaceID = base.spaces[0].id
    func stack(_ axis: SplitAxis, _ parts: (SplitNode, Double)...) -> SplitNode { .stack(axis, parts.map { SplitPart(node: $0.0, share: $0.1) }) }
    let twice = TabSplit(spaceID: spaceID, root: row(ids[0], ids[0]))
    let missing = TabSplit(spaceID: spaceID, root: row(ids[0], UUID()))
    let squeezed = TabSplit(spaceID: spaceID, root: stack(.horizontal, (.pane(ids[0]), 0.01), (.pane(ids[1]), 0.99)))
    let unfilled = TabSplit(spaceID: spaceID, root: stack(.horizontal, (.pane(ids[0]), 0.4), (.pane(ids[1]), 0.4)))
    let alone = TabSplit(spaceID: spaceID, root: stack(.horizontal, (.pane(ids[0]), 1)))
    let nested = TabSplit(spaceID: spaceID, root: stack(.horizontal, (.pane(ids[0]), 0.5), (stack(.horizontal, (.pane(ids[1]), 0.5), (.pane(ids[2]), 0.5)), 0.5)))
    for split in [twice, missing, squeezed, unfilled, alone, nested] {
        let session = BrowserSession(profiles: base.profiles, spaces: base.spaces, tabs: base.tabs, splits: [split])
        #expect(throws: SessionError.inconsistentData) { try session.validate() }
    }
}

@Test func aClosedFavoritePaneComesBackEvenWithoutItsGroup() throws {
    var (session, ids) = session(tabs: 2)
    let spaceID = session.spaces[0].id
    let added = session.addGroup(named: "Reading", in: spaceID)
    let group = try #require(added)
    session.split(ids[1], beside: ids[0], at: .trailing)
    _ = session.move(id: ids[0], to: .list(group: group.id), before: nil)
    let removed = session.close(id: ids[1])
    let closed = try #require(removed)
    session.removeGroup(id: group.id)
    session.restore(closed)
    #expect(session.tabs.first { $0.id == ids[1] }?.place == .list(group: nil), "Its group gone, it is a loose favorite")
    try session.validate()
}
