import BrowserCore
import Darwin
import Foundation
import Observation
import WebKit

/// Owns the session's downloads. They outlive the page that started them: closing or
/// hibernating a tab never interrupts one.
@MainActor @Observable
public final class DownloadCoordinator: NSObject, WKDownloadDelegate {
    private static let whereFromAttribute = "com.apple.metadata:kMDItemWhereFroms"

    public private(set) var downloads: [BrowserDownload] = []
    public var activeCount: Int { downloads.count { $0.state == .downloading } }

    @ObservationIgnored private let directory: URL
    @ObservationIgnored private let fallbackFilename: String

    /// `fallbackFilename` names files the server did not name; it is display text, so the app localizes it.
    public init(directory: URL, fallbackFilename: String) {
        self.directory = directory
        self.fallbackFilename = fallbackFilename
    }

    func isDownloading(from tabID: UUID) -> Bool {
        downloads.contains { $0.sourceTabID == tabID && $0.state == .downloading }
    }

    func track(_ download: WKDownload, from tabID: UUID) {
        let record = BrowserDownload(download: download, sourceTabID: tabID, fallbackFilename: fallbackFilename)
        downloads.insert(record, at: 0)
        attach(download, to: record)
    }

    public func cancel(_ record: BrowserDownload) {
        guard record.state == .downloading else { return }
        record.state = .cancelled
        record.download?.cancel { _ in }
        finish(record)
        removePartialFile(of: record)
    }

    /// Resumes from where the transfer stopped when WebKit kept resume data, otherwise starts over.
    public func retry(_ record: BrowserDownload) {
        guard record.state == .failed || record.state == .cancelled, let store = record.dataStore else { return }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        let view = WKWebView(frame: .zero, configuration: configuration)
        record.resumingView = view
        record.state = .downloading
        record.fractionCompleted = 0
        // WebKit calls these completion handlers on the main thread.
        if let resumeData = record.resumeData {
            record.resumeData = nil
            view.resumeDownload(fromResumeData: resumeData) { [weak self] download in
                MainActor.assumeIsolated { self?.attach(download, to: record) }
            }
        } else if let source = record.sourceURL {
            view.startDownload(using: URLRequest(url: source)) { [weak self] download in
                MainActor.assumeIsolated { self?.attach(download, to: record) }
            }
        }
    }

    public func clearInactive() {
        downloads.removeAll { $0.state != .downloading }
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
        record.progressObservation = nil
        record.download = nil
        record.resumingView = nil
    }

    private func removePartialFile(of record: BrowserDownload) {
        guard let destination = record.destination else { return }
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
        let name = DownloadFilename.available(suggested: suggestedFilename, fallback: fallbackFilename) { candidate in
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(candidate).path)
        }
        let destination = directory.appendingPathComponent(name, isDirectory: false)
        record.filename = name
        record.destination = destination
        return destination
    }

    public func downloadDidFinish(_ download: WKDownload) {
        guard let record = record(for: download) else { return }
        record.completedBytes = download.progress.completedUnitCount
        record.fractionCompleted = 1
        record.state = .finished
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
