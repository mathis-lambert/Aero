import Foundation

/// Work macOS runs about once a day while Aero runs, when it costs the least energy, as it does its own maintenance.
/// Work that could not finish, such as a download without a network, is deferred and asked again later. Ends with
/// its owner.
@MainActor
final class DailyActivity {
    private let scheduler: NSBackgroundActivityScheduler

    /// `work` returns whether it finished.
    init(identifier: String, work: @escaping @MainActor @Sendable () async -> Bool) {
        scheduler = NSBackgroundActivityScheduler(identifier: "\(Bundle.main.bundleIdentifier ?? "Aero").\(identifier)")
        scheduler.repeats = true
        scheduler.interval = 24 * 60 * 60
        scheduler.tolerance = 60 * 60
        scheduler.qualityOfService = .utility
        scheduler.schedule { completion in
            Task { @MainActor in completion(await work() ? .finished : .deferred) }
        }
    }

    isolated deinit { scheduler.invalidate() }
}
