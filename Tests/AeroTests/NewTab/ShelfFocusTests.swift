@testable import Aero
import Testing

// docs/BROWSING.md › New Tab. Written as failure modes first:
// 1. Down from the field enters an empty row, or nothing when only closed tabs are shown.
// 2. A move leaves a row's ends, or vertical moves lose the column or land past a shorter row.
// 3. Up from the sites does not return to the field, or up from the closed tabs skips the sites.
// 4. A focus kept after a row shrinks points past it, so Return opens nothing or the wrong item.

struct ShelfFocusTests {
    private let none: ShelfFocus? = nil

    @Test func downEntersTheFirstRowThatHasItems() {
        #expect(none.moved(.down, sites: 3, closed: 2) == .site(0))
        #expect(none.moved(.down, sites: 0, closed: 2) == .closed(0))
        #expect(none.moved(.down, sites: 0, closed: 0) == nil)
        for move in [ShelfMove.up, .previous, .next] { #expect(none.moved(move, sites: 3, closed: 2) == nil) }
    }

    @Test func movesStayInsideTheirRow() {
        let first: ShelfFocus? = .site(0), last: ShelfFocus? = .site(5)
        #expect(first.moved(.previous, sites: 6, closed: 0) == .site(0))
        #expect(first.moved(.next, sites: 6, closed: 0) == .site(1))
        #expect(last.moved(.next, sites: 6, closed: 0) == .site(5))
        let closed: ShelfFocus? = .closed(2)
        #expect(closed.moved(.next, sites: 6, closed: 3) == .closed(2))
        #expect(closed.moved(.previous, sites: 6, closed: 3) == .closed(1))
        #expect(closed.moved(.down, sites: 6, closed: 3) == .closed(2))
    }

    @Test func verticalMovesKeepTheNearestColumn() {
        let site: ShelfFocus? = .site(4)
        #expect(site.moved(.down, sites: 6, closed: 3) == .closed(2))
        #expect(site.moved(.down, sites: 6, closed: 0) == .site(4), "Without closed tabs, down stays")
        #expect(site.moved(.up, sites: 6, closed: 3) == nil, "Up from the sites is the field")
        let closed: ShelfFocus? = .closed(1)
        #expect(closed.moved(.up, sites: 6, closed: 3) == .site(1))
        #expect((ShelfFocus.closed(2) as ShelfFocus?).moved(.up, sites: 1, closed: 3) == .site(0))
        #expect(closed.moved(.up, sites: 0, closed: 3) == nil)
    }

    @Test func aShrunkRowKeepsTheFocusInside() {
        #expect(ShelfFocus.site(5).clamped(sites: 4, closed: 0) == .site(3))
        #expect(ShelfFocus.site(0).clamped(sites: 0, closed: 2) == nil)
        #expect(ShelfFocus.closed(2).clamped(sites: 6, closed: 1) == .closed(0))
        #expect((ShelfFocus.site(5) as ShelfFocus?).moved(.previous, sites: 3, closed: 0) == .site(1), "Moves start from the clamped place")
    }
}
