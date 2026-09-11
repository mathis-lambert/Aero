import Foundation
import Testing
@testable import BrowserCore

private let now = ContinuousClock.now
private let minute = HibernationSettings.minute
private let settings = HibernationSettings(isEnabled: true, idleLimit: minute * 30, keepsPinnedTabsLoaded: false)

private func candidate(
    idle: Duration,
    active: Bool = false,
    pinned: Bool = false,
    exemptedAgo: Duration? = nil,
    id: UUID = UUID()
) -> HibernationCandidate {
    HibernationCandidate(tabID: id, isActive: active, isPinned: pinned, lastActive: now - idle,
                         lastExemption: exemptedAgo.map { now - $0 })
}

@Test func idlePagesHibernateAndTheActivePageNeverDoes() {
    let idle = candidate(idle: minute * 31)
    let recent = candidate(idle: minute * 10)
    let active = candidate(idle: minute * 90, active: true)
    let plan = HibernationPolicy(settings: settings, liveBackgroundPageLimit: 10)
        .plan(for: [idle, recent, active], now: now)
    #expect(plan.dueTabIDs == [idle.tabID])
    #expect(plan.nextEvaluation == recent.lastActive + settings.idleLimit)
}

@Test func disabledHibernationPlansNothing() {
    var disabled = settings
    disabled.isEnabled = false
    let plan = HibernationPolicy(settings: disabled, pressure: .critical, liveBackgroundPageLimit: 0)
        .plan(for: [candidate(idle: minute * 600)], now: now)
    #expect(plan == HibernationPlan(dueTabIDs: [], nextEvaluation: nil))
}

@Test func pinnedPagesStayLoadedOnlyWhenRequested() {
    let pinned = candidate(idle: minute * 60, pinned: true)
    var keepPinned = settings
    keepPinned.keepsPinnedTabsLoaded = true
    #expect(HibernationPolicy(settings: settings, liveBackgroundPageLimit: 10).plan(for: [pinned], now: now).dueTabIDs == [pinned.tabID])
    #expect(HibernationPolicy(settings: keepPinned, liveBackgroundPageLimit: 10).plan(for: [pinned], now: now).dueTabIDs.isEmpty)
}

@Test func memoryPressureShortensTheIdleLimit() {
    let page = candidate(idle: minute * 6)
    let fresh = candidate(idle: .zero)
    #expect(HibernationPolicy(settings: settings, pressure: .normal, liveBackgroundPageLimit: 10).plan(for: [page], now: now).dueTabIDs.isEmpty)
    #expect(HibernationPolicy(settings: settings, pressure: .warning, liveBackgroundPageLimit: 10).plan(for: [page], now: now).dueTabIDs == [page.tabID])
    #expect(HibernationPolicy(settings: settings, pressure: .critical, liveBackgroundPageLimit: 10).plan(for: [fresh], now: now).dueTabIDs == [fresh.tabID])
}

@Test func pagesBeyondTheBudgetHibernateLeastRecentlyUsedFirst() {
    let oldest = candidate(idle: minute * 3)
    let middle = candidate(idle: minute * 2)
    let newest = candidate(idle: minute)
    let plan = HibernationPolicy(settings: settings, liveBackgroundPageLimit: 1)
        .plan(for: [newest, oldest, middle], now: now)
    #expect(plan.dueTabIDs == [oldest.tabID, middle.tabID])
}

@Test func exemptPagesAreRecheckedLaterAndDoNotConsumeTheBudget() {
    let exempt = candidate(idle: minute * 3, exemptedAgo: minute)
    let other = candidate(idle: minute * 2)
    let newest = candidate(idle: minute)
    let plan = HibernationPolicy(settings: settings, liveBackgroundPageLimit: 2)
        .plan(for: [exempt, other, newest], now: now)
    #expect(plan.dueTabIDs == [other.tabID])
    #expect(plan.nextEvaluation == now - minute + HibernationPolicy.exemptionRecheckInterval)
}

@Test func liveBudgetScalesWithPhysicalMemoryWithinBounds() {
    let gibibyte: UInt64 = 1 << 30
    #expect(HibernationPolicy.liveBackgroundPageLimit(forPhysicalMemory: 8 * gibibyte) == 4)
    #expect(HibernationPolicy.liveBackgroundPageLimit(forPhysicalMemory: 16 * gibibyte) == 8)
    #expect(HibernationPolicy.liveBackgroundPageLimit(forPhysicalMemory: gibibyte) == 2)
    #expect(HibernationPolicy.liveBackgroundPageLimit(forPhysicalMemory: 512 * gibibyte) == 24)
}
