import BrowserCore
import Foundation

/// Hibernation runs as one owned task that sleeps until the next deadline, so an idle browser
/// has no periodic wakeups. Activity, settings, pins and memory pressure reschedule it.
extension WebPageRegistry {
    public func refreshHibernationSchedule() {
        evaluation?.cancel()
        evaluation = Task { [weak self] in
            while !Task.isCancelled {
                guard let next = await self?.hibernateDuePages() else { return }
                do {
                    try await Task.sleep(until: next, tolerance: HibernationPolicy.schedulingTolerance, clock: .continuous)
                } catch { return }
            }
        }
    }

    /// Returns the next deadline, or `nil` when nothing remains to schedule.
    @discardableResult
    func hibernateDuePages() async -> ContinuousClock.Instant? {
        var plan = hibernationPlan()
        while !plan.dueTabIDs.isEmpty, !Task.isCancelled {
            await hibernate(plan.dueTabIDs)
            plan = hibernationPlan()
        }
        return Task.isCancelled ? nil : plan.nextEvaluation
    }

    func hibernationPlan() -> HibernationPlan {
        let candidates = livePages.map { tabID, live in
            HibernationCandidate(tabID: tabID, isActive: tabID == activeTabID, isPinned: delegate?.isPinned(tabID) == true,
                                 lastActive: live.lastActive, lastExemption: live.lastExemption)
        }
        return policy.plan(for: candidates, now: .now)
    }

    /// Checks each page for state that cannot be restored; a page that becomes active or closes
    /// during the check is left alone.
    func hibernate(_ tabIDs: [UUID]) async {
        for tabID in tabIDs {
            guard !Task.isCancelled, let page = livePages[tabID]?.page else { continue }
            if hasPopupRelationship(tabID) {
                livePages[tabID]?.lastExemption = .now
                continue
            }
            let interval = Self.signposter.beginInterval(Diagnostics.Signpost.hibernationCheck)
            let blocker = await page.hibernationBlocker()
            Self.signposter.endInterval(Diagnostics.Signpost.hibernationCheck, interval)
            guard livePages[tabID]?.page === page, tabID != activeTabID else { continue }
            if blocker == nil { hibernate(tabID) }
            else { livePages[tabID]?.lastExemption = .now }
        }
    }
}
