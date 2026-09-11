import Foundation

public struct HibernationSettings: Equatable, Sendable {
    public static let minute = Duration.seconds(60)
    public static let idleLimitOptions: [Duration] = [15, 30, 60, 120, 240].map { minute * $0 }
    public static let `default` = HibernationSettings(isEnabled: true, idleLimit: minute * 30, keepsPinnedTabsLoaded: false)

    public var isEnabled: Bool
    public var idleLimit: Duration
    public var keepsPinnedTabsLoaded: Bool

    public init(isEnabled: Bool, idleLimit: Duration, keepsPinnedTabsLoaded: Bool) {
        self.isEnabled = isEnabled
        self.idleLimit = idleLimit
        self.keepsPinnedTabsLoaded = keepsPinnedTabsLoaded
    }
}

public enum MemoryPressure: Sendable {
    case normal, warning, critical
}
