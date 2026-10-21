import Foundation

/// A transfer's speed over its last few seconds, and the time left at that speed. Recent samples only, so the
/// estimate follows a connection that speeds up or slows down, without jumping at every packet.
public struct TransferRate: Sendable {
    /// The span of samples the speed is measured over.
    static let window: TimeInterval = 4
    /// The shortest span that gives a speed; before it, a first burst would read as a very fast transfer.
    static let minimumSpan: TimeInterval = 1

    private var samples: [(time: TimeInterval, bytes: Int64)] = []

    public init() {}

    /// Records the bytes transferred so far at `time`, in seconds on a monotonic clock. Fewer bytes than before means
    /// the transfer started over: the earlier samples no longer apply.
    public mutating func record(bytes: Int64, at time: TimeInterval) {
        if let last = samples.last, bytes < last.bytes || time < last.time { samples.removeAll() }
        samples.append((time, bytes))
        // Keeps the newest sample at or before the window's start, so the span still covers the whole window.
        while samples.count > 2, samples[1].time <= time - Self.window { samples.removeFirst() }
    }

    /// Bytes per second, or `nil` until the samples span long enough.
    public var bytesPerSecond: Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let span = last.time - first.time
        guard span >= Self.minimumSpan else { return nil }
        return Double(last.bytes - first.bytes) / span
    }

    /// The time left for the bytes still to come at the current speed; `nil` without a size or a speed.
    public func remaining(totalBytes: Int64?) -> Duration? {
        guard let totalBytes, let rate = bytesPerSecond, rate > 0, let completed = samples.last?.bytes else { return nil }
        return .seconds((Double(max(0, totalBytes - completed)) / rate).rounded(.up))
    }
}
