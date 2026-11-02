@testable import Aero
import BrowserCore
import Foundation
import Testing

// Failure modes: the stateful lazy filter traps when materialized; duplicates consume the three slots;
// tabs from another space leak into the shelf; the oldest duplicate is kept instead of the newest.
struct RecentlyClosedTests {
    @Test func keepsTheThreeNewestDistinctPagesOfTheCurrentSpace() throws {
        let space = UUID(), other = UUID()
        func tab(_ path: String, in id: UUID) throws -> BrowserTab {
            BrowserTab(spaceID: id, url: try #require(URL(string: "https://example.test/" + path)))
        }
        let oldest = try tab("old", in: space)
        let a = try tab("a", in: space), b = try tab("b", in: space)
        let duplicate = try tab("a", in: space), c = try tab("c", in: space)
        let foreign = try tab("foreign", in: other)
        let closed = NewTabShelf.recentlyClosed([oldest, a, b, duplicate, c, foreign], in: space)
        #expect(closed.map(\.id) == [c.id, duplicate.id, b.id])
        #expect(NewTabShelf.recentlyClosed([a, duplicate], in: space).map(\.id) == [duplicate.id])
        #expect(NewTabShelf.recentlyClosed([a, foreign], in: UUID()).isEmpty)
        #expect(NewTabShelf.recentlyClosed([a], in: nil).isEmpty)
        #expect(NewTabShelf.recentlyClosed([], in: space).isEmpty)
    }
}
