import AppKit
import CoreGraphics
import Foundation

/// Reports active, idle or locked state. Checks follow listeners' detection intervals and stop without listeners.
@MainActor
final class IdleMonitor {
    enum State: String, Sendable { case active, idle, locked }

    /// Chrome's shortest detection interval, and its default.
    nonisolated static let minimumInterval = 15
    nonisolated static let defaultInterval = 60
    /// While idle, how soon input brings the state back to active.
    nonisolated static let idleCheck = Duration.seconds(5)

    var onChange: (() -> Void)?
    private(set) var isLocked = false
    private var intervals: [Int] = []
    private var observers: [any NSObjectProtocol] = []
    private var check: Task<Void, Never>?

    isolated deinit { stop() }

    /// Seconds since the last keyboard, pointer or touch input in the session.
    var idleSeconds: Int {
        // Every input event type, as Core Graphics' `kCGAnyInputEventType` names it.
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return Int(CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput))
    }

    func state(forInterval interval: Int) -> State {
        if isLocked { return .locked }
        return idleSeconds >= max(interval, Self.minimumInterval) ? .idle : .active
    }

    /// The detection intervals listeners use; none stops watching.
    func watch(intervals: [Int]) {
        self.intervals = intervals.map { max($0, Self.minimumInterval) }
        if self.intervals.isEmpty { stop() } else { start() }
    }

    private func start() {
        if observers.isEmpty {
            // The screen lock's own notifications, as the system posts them for any app.
            let center = DistributedNotificationCenter.default()
            observers = [("com.apple.screenIsLocked", true), ("com.apple.screenIsUnlocked", false)].map { name, locked in
                center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.setLocked(locked) }
                }
            }
        }
        schedule()
    }

    private func stop() {
        for observer in observers { DistributedNotificationCenter.default().removeObserver(observer) }
        observers = []
        check?.cancel()
        check = nil
    }

    private func setLocked(_ locked: Bool) {
        guard locked != isLocked else { return }
        isLocked = locked
        onChange?()
        schedule()
    }

    /// When to check again: as the next interval elapses without input, or soon while some interval is idle, since
    /// only a check sees input come back.
    nonisolated static func nextCheck(idleSeconds idle: Int, intervals: [Int]) -> Duration {
        let pending = intervals.filter { $0 > idle }.map { Duration.seconds($0 - idle) }.min()
        guard intervals.contains(where: { $0 <= idle }) else { return pending ?? idleCheck }
        return min(pending ?? idleCheck, idleCheck)
    }

    private func schedule() {
        check?.cancel()
        guard !intervals.isEmpty, !isLocked else { return }
        let delay = Self.nextCheck(idleSeconds: idleSeconds, intervals: intervals)
        check = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            self?.onChange?()
            self?.schedule()
        }
    }
}
