import Foundation
import Testing
@testable import BrowserCore

// Failure modes: repeated steps reorder MRU; reverse cycling does not wrap; New Tab skips the most recent
// page; closed/foreign tabs survive the snapshot; no tabs or one tab divides by zero or changes selection.
struct RecentTabCycleTests {
    @Test func freezesOrderAndWrapsInBothDirections() {
        let a = UUID(), b = UUID(), c = UUID(), foreign = UUID()
        var cycle = RecentTabCycle(tabs: [a, b, c], recent: [b, foreign, a, b], selected: b)
        #expect(cycle.tabs == [b, a, c])
        cycle.step(backwards: false)
        #expect(cycle.selected == a)
        cycle.step(backwards: false)
        #expect(cycle.selected == c)
        cycle.step(backwards: false)
        #expect(cycle.selected == b)
        cycle.step(backwards: true)
        #expect(cycle.selected == c)
    }

    @Test func newTabStartsAtTheMostRecentPage() {
        let a = UUID(), b = UUID()
        var forward = RecentTabCycle(tabs: [a, b], recent: [b], selected: nil)
        forward.step(backwards: false)
        #expect(forward.selected == b)
        var reverse = RecentTabCycle(tabs: [a, b], recent: [b], selected: nil)
        reverse.step(backwards: true)
        #expect(reverse.selected == a)
        var empty = RecentTabCycle(tabs: [], recent: [a], selected: a)
        empty.step(backwards: false)
        #expect(empty.selected == nil)
        var single = RecentTabCycle(tabs: [a], recent: [], selected: a)
        single.step(backwards: true)
        #expect(single.selected == a)
    }
}
