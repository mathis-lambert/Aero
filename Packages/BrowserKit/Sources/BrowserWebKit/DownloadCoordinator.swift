import BrowserCore
import Darwin
import Foundation
import Observation
import WebKit

/// Why a downloaded file could not be renamed.
public enum DownloadRenameError: Error, Equatable {
    /// Nothing usable is left of the name, or it is too long.
    case invalidName
    /// Another file in the folder has that name.
    case nameTaken
    /// The file is no longer where it was downloaded.
    case fileMissing
    /// The disk refused, for permission or another reason.
    case notRenamed
}

/// Owns the session's downloads. They outlive the page that started them: closing or
/// hibernating a tab never interrupts one.
@MainActor @Observable
public final class DownloadCoordinator: NSObject, WKDownloadDelegate {
    private static let whereFromAttribute = "com.apple.metadata:kMDItemWhereFroms"

    public private(set) var downloads: [BrowserDownload] = []
    /// The download started last this session; retries and clearing leave it unchanged.
    public private(set) var lastStarted: BrowserDownload.ID?
    public var activeCount: Int { downloads.count { $0.state == .downloading } }

    /// Where downloads are saved.
    @ObservationIgnored public let directory: URL
    @ObservationIgnored private let fallbackFilename: String

    /// `fallbackFilename` names files the server did not name; it is display text, so the app localizes it.
    public init(directory: URL, fallbackFilename: String) {
        self.directory = directory
        self.fallbackFilename = fallbackFilename
    }

    public func isDownloading(from tabID: UUID) -> Bool {
        downloads.contains { $0.sourceTabID == tabID && $0.state == .downloading }
    }

    @discardableResult
    func track(_ download: WKDownload, from tabID: UUID?) -> BrowserDownload {
        let record = BrowserDownload(download: download, sourceTabID: tabID, fallbackFilename: fallbackFilename)
        downloads.insert(record, at: 0)
        lastStarted = record.id
        attach(download, to: record)
        return record
    }

    /// A download an extension asked for, with the website data of its profile, listed with the others.
    /// `filename`, when given, replaces the name the server suggests.
    public func start(_ request: URLRequest, in store: WKWebsiteDataStore, filename: String?) async -> BrowserDownload {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        configuration.applicationNameForUserAgent = BrowserIdentity.applicationNameForUserAgent
        let view = WKWebView(frame: .zero, configuration: configuration)
        return await withCheckedContinuation { continuation in
            // Tracked in the completion handler, on the main thread: past an `await`, the response could reach a
            // download without a delegate, which WebKit cancels.
            view.startDownload(using: request) { download in
                MainActor.assumeIsolated {
                    let record = self.track(download, from: nil)
                    record.requestedFilename = filename
                    // The view starts the transfer; the download keeps its own connection once it has begun.
                    record.resumingView = view
                    continuation.resume(returning: record)
                }
            }
        }
    }

    public func cancel(_ record: BrowserDownload) {
        guard record.state == .downloading || record.state == .paused else { return }
        record.state = .cancelled
        record.resumeData = nil
        record.awaitingResumeData = false
        record.resumesWhenReady = false
        record.download?.cancel { _ in }
        finish(record)
        removePartialFile(of: record)
    }

    /// Stops the transfer, keeping what WebKit needs to continue it later where it stopped, when the server allows.
    public func pause(_ record: BrowserDownload) {
        guard record.state == .downloading, let download = record.download else { return }
        record.state = .paused
        record.awaitingResumeData = true
        detach(record)
        download.cancel { [weak self] resumeData in
            Task { @MainActor in
                // Cancelled meanwhile: the data no longer applies.
                guard record.state == .paused, record.awaitingResumeData else { return }
                record.awaitingResumeData = false
                record.resumeData = resumeData
                if record.resumesWhenReady {
                    record.resumesWhenReady = false
                    self?.restart(record)
                }
            }
        }
    }

    /// Continues a paused download where it stopped, or from the start when the server cannot resume. Asked before
    /// WebKit has handed back what it needs to continue, it waits for it rather than starting over.
    public func resume(_ record: BrowserDownload) {
        guard record.state == .paused else { return }
        if record.awaitingResumeData { record.resumesWhenReady = true } else { restart(record) }
    }

    /// Resumes from where the transfer stopped when WebKit kept resume data, otherwise starts over.
    public func retry(_ record: BrowserDownload) {
        guard record.state == .failed || record.state == .cancelled else { return }
        restart(record)
    }

    /// Renames a finished download's file in its folder. A name that is already taken is refused, never replaced.
    public func rename(_ record: BrowserDownload, to name: String) throws(DownloadRenameError) {
        guard record.state == .finished, let source = record.destination else { throw .fileMissing }
        guard let name = DownloadFilename.renamed(name) else { throw .invalidName }
        guard name != record.filename else { return }
        let target = source.deletingLastPathComponent().appendingPathComponent(name, isDirectory: false)
        // The name must be free, checked as the file moves. Only a change of case on a disk that ignores case finds the
        // file itself there.
        if renamex_np(source.path, target.path, UInt32(RENAME_EXCL)) != 0 {
            var failure = errno
            if failure == EEXIST, Self.isSameFile(source, target) {
                failure = Darwin.rename(source.path, target.path) == 0 ? 0 : errno
            }
            switch failure {
            case 0: break
            case EEXIST: throw .nameTaken
            case ENOENT: throw .fileMissing
            default: throw .notRenamed
            }
        }
        record.filename = name
        record.destination = target
    }

    /// Moves a finished download's file to the Trash, where it can be put back, and takes it off the list. A file
    /// already gone leaves the list all the same.
    public func moveToTrash(_ record: BrowserDownload) throws {
        guard record.state == .finished, let file = record.destination else { return }
        do {
            try FileManager.default.trashItem(at: file, resultingItemURL: nil)
        } catch CocoaError.fileNoSuchFile {}
        downloads.removeAll { $0 === record }
    }

    /// Takes a download that no longer transfers off the list; its file stays.
    public func remove(_ record: BrowserDownload) {
        guard record.state != .downloading, record.state != .paused else { return }
        downloads.removeAll { $0 === record }
    }

    private func restart(_ record: BrowserDownload) {
        guard record.resumeData != nil || record.sourceURL != nil, let store = record.dataStore else { return }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        configuration.applicationNameForUserAgent = BrowserIdentity.applicationNameForUserAgent
        let view = WKWebView(frame: .zero, configuration: configuration)
        let wasCancelled = record.state == .cancelled
        record.resumingView = view
        record.state = .downloading
        record.endTime = nil
        if record.resumeData == nil {
            // Starting over: what was written of the file no longer applies. A cancelled download's was removed then,
            // and its name may since belong to another file.
            if !wasCancelled { removePartialFile(of: record) }
            record.fractionCompleted = 0
            record.completedBytes = 0
            record.totalBytes = nil
        }
        // WebKit calls these completion handlers on the main thread.
        let started: @Sendable (WKDownload) -> Void = { [weak self] download in
            MainActor.assumeIsolated {
                guard let self, record.state == .downloading, record.resumingView === view else {
                    download.cancel { _ in }
                    return
                }
                self.attach(download, to: record)
            }
        }
        if let resumeData = record.resumeData {
            record.resumeData = nil
            view.resumeDownload(fromResumeData: resumeData, completionHandler: started)
        } else if let source = record.sourceURL {
            view.startDownload(using: URLRequest(url: source), completionHandler: started)
        }
    }

    public func clearInactive() {
        downloads.removeAll { $0.state != .downloading && $0.state != .paused }
    }

    private func attach(_ download: WKDownload, to record: BrowserDownload) {
        record.download = download
        download.delegate = self
        // WebKit updates download progress on the main thread, for every packet received.
        record.progressObservation = download.progress.observe(\.fractionCompleted) { [weak record] progress, _ in
            MainActor.assumeIsolated { record?.updateProgress(progress) }
        }
    }

    private func record(for download: WKDownload) -> BrowserDownload? {
        downloads.first { $0.download === download }
    }

    private func finish(_ record: BrowserDownload) {
        record.endTime = .now
        detach(record)
    }

    /// Lets go of the transfer: its progress in the Finder, its observation and the view that started it.
    private func detach(_ record: BrowserDownload) {
        record.download?.progress.unpublish()
        record.progressObservation = nil
        record.download = nil
        record.resumingView = nil
        record.resetRate()
    }

    private static func isSameFile(_ first: URL, _ second: URL) -> Bool {
        var firstStatus = stat(), secondStatus = stat()
        return stat(first.path, &firstStatus) == 0 && stat(second.path, &secondStatus) == 0
            && firstStatus.st_dev == secondStatus.st_dev && firstStatus.st_ino == secondStatus.st_ino
    }

    private func removePartialFile(of record: BrowserDownload) {
        // Another download may have landed at that name since this one stopped.
        guard let destination = record.destination, !downloads.contains(where: { $0 !== record && $0.destination == destination }) else { return }
        // Best effort: the file only exists if WebKit already started writing it.
        try? FileManager.default.removeItem(at: destination)
    }

    /// Records the source like Safari, for Finder's "Where from". Best effort: the file is complete without it.
    private func recordSource(of record: BrowserDownload) {
        guard let destination = record.destination, let source = record.sourceURL?.absoluteString,
              let data = try? PropertyListSerialization.data(fromPropertyList: [source], format: .binary, options: 0) else { return }
        _ = data.withUnsafeBytes { bytes in
            setxattr(destination.path, Self.whereFromAttribute, bytes.baseAddress, bytes.count, 0, 0)
        }
    }

    // MARK: - WKDownloadDelegate

    public func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        guard let record = record(for: download) else { return nil }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let name = DownloadFilename.available(suggested: record.requestedFilename ?? suggestedFilename, fallback: fallbackFilename) { candidate in
            let url = directory.appendingPathComponent(candidate)
            return FileManager.default.fileExists(atPath: url.path)
                || downloads.contains { $0 !== record && $0.state == .downloading && $0.destination == url }
        }
        let destination = directory.appendingPathComponent(name, isDirectory: false)
        record.finalURL = response.url
        record.mimeType = response.mimeType
        record.filename = name
        record.destination = destination
        // Finder and the Dock show the transfer on the file, as for Safari's downloads.
        download.progress.kind = .file
        download.progress.fileOperationKind = .downloading
        download.progress.fileURL = destination
        download.progress.publish()
        return destination
    }

    public func downloadDidFinish(_ download: WKDownload) {
        guard let record = record(for: download) else { return }
        record.completedBytes = download.progress.completedUnitCount
        record.fractionCompleted = 1
        record.state = .finished
        record.resumeData = nil
        recordSource(of: record)
        finish(record)
    }

    public func download(_ download: WKDownload, didFailWithError error: any Error, resumeData: Data?) {
        guard let record = record(for: download), record.state == .downloading else { return }
        record.state = .failed
        record.resumeData = resumeData
        finish(record)
    }
}
