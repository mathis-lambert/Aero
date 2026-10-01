import Foundation
import Observation
import WebKit

@MainActor @Observable
public final class BrowserDownload: Identifiable {
    public enum State: Equatable {
        case downloading, finished, failed, cancelled
    }

    /// Progress is published in whole percents (or byte steps when the size is unknown), so a
    /// fast download does not redraw the sidebar for every packet.
    static let progressStep = 0.01
    static let unknownSizeStep: Int64 = 256 * 1024

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

    /// `nil` for a download an extension started.
    @ObservationIgnored let sourceTabID: UUID?
    /// The name an extension asked for, in place of the one the server suggests.
    @ObservationIgnored var requestedFilename: String?
    @ObservationIgnored let dataStore: WKWebsiteDataStore?
    @ObservationIgnored var download: WKDownload?
    @ObservationIgnored var resumeData: Data?
    /// WebKit kept what the transfer needs to continue where it stopped.
    public var canResume: Bool { resumeData != nil }
    /// A detached view that resumes a download whose page is gone; released when it ends.
    @ObservationIgnored var resumingView: WKWebView?
    @ObservationIgnored var progressObservation: NSKeyValueObservation?

    init(download: WKDownload, sourceTabID: UUID?, fallbackFilename: String) {
        self.download = download
        self.sourceTabID = sourceTabID
        sourceURL = download.originalRequest?.url
        dataStore = download.webView?.configuration.websiteDataStore
        let lastComponent = sourceURL?.lastPathComponent ?? ""
        filename = lastComponent.isEmpty || lastComponent == "/" ? fallbackFilename : lastComponent
    }

    func updateProgress(_ progress: Progress) {
        let total = progress.totalUnitCount > 0 ? progress.totalUnitCount : nil
        let fraction = total == nil ? 0 : progress.fractionCompleted
        let isStep = total == nil
            ? progress.completedUnitCount - completedBytes >= Self.unknownSizeStep
            : fraction - fractionCompleted >= Self.progressStep || fraction >= 1
        guard isStep else { return }
        fractionCompleted = fraction
        completedBytes = progress.completedUnitCount
        totalBytes = total
    }
}
