import Foundation

public struct HibernationSettings: Equatable, Sendable {
    public static let minute = Duration.seconds(60)
    public static let idleLimitOptions: [Duration] = [15, 30, 60, 120, 240].map { minute * $0 }
    public static let `default` = HibernationSettings(isEnabled: true, idleLimit: minute * 30, keepsFavoritesLoaded: false)

    public var isEnabled: Bool
    public var idleLimit: Duration
    public var keepsFavoritesLoaded: Bool

    package init(isEnabled: Bool, idleLimit: Duration, keepsFavoritesLoaded: Bool) {
        self.isEnabled = isEnabled
        self.idleLimit = idleLimit
        self.keepsFavoritesLoaded = keepsFavoritesLoaded
    }
}

package enum MemoryPressure: Sendable {
    case normal, warning, critical
}
