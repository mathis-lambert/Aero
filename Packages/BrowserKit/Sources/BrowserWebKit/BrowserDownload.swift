import BrowserCore
import Foundation
import Observation
import WebKit

@MainActor @Observable
public final class BrowserDownload: Identifiable {
    public enum State: Equatable {
        /// `paused` stopped at the user's request; it resumes where it stopped when WebKit kept resume data.
        case downloading, paused, finished, failed, cancelled
    }

    /// Progress is published in whole percents (or byte steps when the size is unknown), or at least this often for
    /// the speed, so a fast download does not redraw the sidebar for every packet.
    static let progressStep = 0.01
    static let unknownSizeStep: Int64 = 256 * 1024
    static let progressInterval: TimeInterval = 0.5

    public let id = UUID()
    public let sourceURL: URL?
    /// The address the server answered from, after redirects.
    public internal(set) var finalURL: URL?
    public internal(set) var mimeType: String?
    public internal(set) var endTime: Date?
    public internal(set) var filename: String
    public internal(set) var destination: URL?
    public internal(set) var state = State.downloading
    public internal(set) var fractionCompleted = 0.0
    public internal(set) var completedBytes: Int64 = 0
    /// `nil` while the server has not announced a size.
    public internal(set) var totalBytes: Int64?
    /// `nil` until the transfer has run long enough to measure.
    public internal(set) var bytesPerSecond: Double?
    /// The time left at the current speed; `nil` without a size or a speed.
    public internal(set) var remainingTime: Duration?

    /// `nil` for a download an extension started.
    @ObservationIgnored let sourceTabID: UUID?
    /// The name an extension asked for, in place of the one the server suggests.
    @ObservationIgnored var requestedFilename: String?
    @ObservationIgnored let dataStore: WKWebsiteDataStore?
    @ObservationIgnored var download: WKDownload?
    @ObservationIgnored var resumeData: Data?
    /// Paused, WebKit has not yet handed back what it needs to continue; a resume asked meanwhile waits for it.
    @ObservationIgnored var awaitingResumeData = false
    @ObservationIgnored var resumesWhenReady = false
    /// WebKit kept what the transfer needs to continue where it stopped.
    public var canResume: Bool { resumeData != nil }
    /// A detached view that resumes a download whose page is gone; released when it ends.
    @ObservationIgnored var resumingView: WKWebView?
    @ObservationIgnored var progressObservation: NSKeyValueObservation?
    @ObservationIgnored private var rate = TransferRate()
    @ObservationIgnored private var publishedAt: TimeInterval = 0

    init(download: WKDownload, sourceTabID: UUID?, fallbackFilename: String) {
        self.download = download
        self.sourceTabID = sourceTabID
        sourceURL = download.originalRequest?.url
        dataStore = download.webView?.configuration.websiteDataStore
        let lastComponent = sourceURL?.lastPathComponent ?? ""
        filename = lastComponent.isEmpty || lastComponent == "/" ? fallbackFilename : lastComponent
    }

    func updateProgress(_ progress: Progress, at time: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        let total = progress.totalUnitCount > 0 ? progress.totalUnitCount : nil
        let fraction = total == nil ? 0 : progress.fractionCompleted
        let isStep = total == nil
            ? progress.completedUnitCount - completedBytes >= Self.unknownSizeStep
            : fraction - fractionCompleted >= Self.progressStep || fraction >= 1
        guard isStep || time - publishedAt >= Self.progressInterval else { return }
        publishedAt = time
        rate.record(bytes: progress.completedUnitCount, at: time)
        fractionCompleted = fraction
        completedBytes = progress.completedUnitCount
        totalBytes = total
        bytesPerSecond = rate.bytesPerSecond
        remainingTime = rate.remaining(totalBytes: total)
    }

    /// Forgets the speed once the transfer stops; the next one measures afresh.
    func resetRate() {
        rate = TransferRate()
        bytesPerSecond = nil
        remainingTime = nil
    }
}
