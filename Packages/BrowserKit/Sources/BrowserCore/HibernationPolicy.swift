import Foundation

package struct HibernationCandidate: Sendable {
    package let tabID: UUID
    package let isActive: Bool
    package let isPinned: Bool
    package let lastActive: ContinuousClock.Instant
    package let lastExemption: ContinuousClock.Instant?

    package init(tabID: UUID, isActive: Bool, isPinned: Bool, lastActive: ContinuousClock.Instant, lastExemption: ContinuousClock.Instant?) {
        self.tabID = tabID
        self.isActive = isActive
        self.isPinned = isPinned
        self.lastActive = lastActive
        self.lastExemption = lastExemption
    }
}

package struct HibernationPlan: Equatable, Sendable {
    /// Least recently used first.
    package let dueTabIDs: [UUID]
    package let nextEvaluation: ContinuousClock.Instant?
}

/// Decides which live pages to unload: idle pages, the oldest pages beyond the memory budget,
/// and every eligible page under critical memory pressure.
package struct HibernationPolicy: Sendable {
    package static let pressuredIdleLimit = HibernationSettings.minute * 5
    package static let exemptionRecheckInterval = HibernationSettings.minute * 5
    package static let schedulingTolerance = HibernationSettings.minute
    private static let bytesPerLiveBackgroundPage: UInt64 = 2 << 30
    private static let liveBackgroundPageRange = 2...24

    package var settings: HibernationSettings
    package var pressure: MemoryPressure
    package var liveBackgroundPageLimit: Int

    package init(settings: HibernationSettings, pressure: MemoryPressure = .normal, liveBackgroundPageLimit: Int) {
        self.settings = settings
        self.pressure = pressure
        self.liveBackgroundPageLimit = liveBackgroundPageLimit
    }

    package static func liveBackgroundPageLimit(forPhysicalMemory bytes: UInt64) -> Int {
        let pages = Int(bytes / bytesPerLiveBackgroundPage)
        return min(max(pages, liveBackgroundPageRange.lowerBound), liveBackgroundPageRange.upperBound)
    }

    private var idleLimit: Duration {
        switch pressure {
        case .normal: settings.idleLimit
        case .warning: min(settings.idleLimit, Self.pressuredIdleLimit)
        case .critical: .zero
        }
    }

    package func plan(for candidates: [HibernationCandidate], now: ContinuousClock.Instant) -> HibernationPlan {
        guard settings.isEnabled else { return HibernationPlan(dueTabIDs: [], nextEvaluation: nil) }
        let background = candidates.filter { !$0.isActive }
        let eligible = background
            .filter { !(settings.keepsPinnedTabsLoaded && $0.isPinned) }
            .sorted { $0.lastActive < $1.lastActive }
        var overflow = background.count - liveBackgroundPageLimit
        var due: [UUID] = []
        var next: ContinuousClock.Instant?
        for candidate in eligible {
            let idleDeadline = overflow > 0 ? now : candidate.lastActive + idleLimit
            let recheck = candidate.lastExemption.map { $0 + Self.exemptionRecheckInterval } ?? idleDeadline
            let deadline = max(idleDeadline, recheck)
            if deadline <= now {
                due.append(candidate.tabID)
                overflow -= 1
            } else {
                next = min(next ?? deadline, deadline)
            }
        }
        return HibernationPlan(dueTabIDs: due, nextEvaluation: next)
    }
}
