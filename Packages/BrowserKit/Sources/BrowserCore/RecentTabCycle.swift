import Foundation

/// One held-modifier gesture. The order stays frozen until commit; stepping never activates a page.
public struct RecentTabCycle: Equatable, Sendable {
    public let tabs: [UUID]
    private var index: Int?
    public var selected: UUID? { index.map { tabs[$0] } }

    public init(tabs: [UUID], recent: [UUID], selected: UUID?) {
        let allowed = Set(tabs)
        var seen: Set<UUID> = []
        self.tabs = (recent + tabs).filter { allowed.contains($0) && seen.insert($0).inserted }
        index = selected.flatMap { self.tabs.firstIndex(of: $0) }
    }

    public mutating func step(backwards: Bool) {
        guard !tabs.isEmpty else { return }
        guard let index else {
            self.index = backwards ? tabs.count - 1 : 0
            return
        }
        self.index = (index + (backwards ? -1 : 1) + tabs.count) % tabs.count
    }
}
