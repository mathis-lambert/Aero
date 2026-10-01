import Testing
@testable import BrowserExtensions

// When `idle` checks again. Failure modes: missing the moment an interval elapses, polling while nothing can change
// soon, and never seeing input come back once idle.

@Test func activeChecksWhenTheNearestIntervalElapses() {
    #expect(IdleMonitor.nextCheck(idleSeconds: 10, intervals: [60, 30]) == .seconds(20))
}

@Test func idleChecksSoonForInputComingBack() {
    #expect(IdleMonitor.nextCheck(idleSeconds: 90, intervals: [60]) == IdleMonitor.idleCheck)
    #expect(IdleMonitor.nextCheck(idleSeconds: 40, intervals: [30, 42]) == .seconds(2), "An interval about to elapse still comes first")
    #expect(IdleMonitor.nextCheck(idleSeconds: 40, intervals: [30, 300]) == IdleMonitor.idleCheck)
}
