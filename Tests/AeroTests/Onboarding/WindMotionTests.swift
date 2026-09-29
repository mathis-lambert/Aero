@testable import Aero
import Foundation
import Testing

// Failure modes:
// 1. A gust is still lively at the first settling deadline, then never releases the display cadence.
// 2. A morph or ripple keeps the wind active after its effect has ended.
// 3. Reduce Motion shows an intermediate shape instead of the completed one.
struct WindMotionTests {
    @Test func aGustSettlesAsFramesAdvance() {
        let motion = WindMotion()
        motion.gust(forward: true)
        let start = Date.now
        var frame = motion.advance(to: start, flowing: false, allowsMotion: true)
        for tick in 1...48 {
            frame = motion.advance(to: start.addingTimeInterval(Double(tick) / 30), flowing: false, allowsMotion: true)
        }
        #expect(frame.isLively, "A gust can still need the display cadence after 1.6 seconds")
        for tick in 49...120 {
            frame = motion.advance(to: start.addingTimeInterval(Double(tick) / 30), flowing: false, allowsMotion: true)
        }
        #expect(!frame.isLively, "The frame releases the high cadence once the gust has decayed")
    }

    @Test func shapesAndRipplesSettle() {
        let motion = WindMotion()
        motion.startMorph(duration: 1.9)
        motion.ripple(WindRipple(origin: .zero))
        let start = Date.now
        #expect(motion.advance(to: start, flowing: false, allowsMotion: true).isLively)
        let settled = motion.advance(to: start.addingTimeInterval(2), flowing: false, allowsMotion: true)
        #expect(!settled.isLively)
        #expect(settled.morph == 1)
    }

    @Test func reducedMotionCompletesTheShapeImmediately() {
        let motion = WindMotion()
        motion.startMorph(duration: 1.9)
        #expect(motion.advance(to: .now, flowing: false, allowsMotion: false).morph == 1)
    }
}
