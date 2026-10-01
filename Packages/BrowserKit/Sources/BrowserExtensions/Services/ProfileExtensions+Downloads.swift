import AppKit
import BrowserCore
import Foundation
import Observation
import WebKit

extension ProfileExtensions {
    // MARK: - Downloads

    private static let downloadSchemes: Set = ["http", "https", "data"]

    func downloadsRequest(_ action: String, _ body: [String: Any], of extensionID: String) async throws -> Any? {
        func tracked() throws -> TrackedDownload {
            guard let id = body["id"] as? Int, let download = downloads[extensionID]?[id] else { throw DownloadFailure.unknown }
            return download
        }
        switch action {
        case "download": return try await startDownload(body, for: extensionID)
        case "search": return downloadItems(of: extensionID, matching: body)
        case "cancel": try tracked().download.cancel()
        case "show": host?.revealDownloads(try tracked().download.destination)
        case "showFolder": host?.revealDownloads(nil)
        case "erase": return eraseDownloads(of: extensionID, matching: body)
        default: throw ExtensionBridge.Failure.unknownRequest
        }
        return nil
    }

    enum DownloadFailure: LocalizedError {
        case unknown
        var errorDescription: String? { "Invalid download id." }
    }

    func startDownload(_ body: [String: Any], for extensionID: String) async throws -> Int {
        guard let url = (body["url"] as? String).flatMap(URL.init(string:)), let scheme = url.scheme?.lowercased(),
              Self.downloadSchemes.contains(scheme), let host else { throw ExtensionBridge.Failure.invalidRequest }
        var request = URLRequest(url: url)
        request.httpMethod = (body["method"] as? String) == "POST" ? "POST" : "GET"
        for header in (body["headers"] as? [[String: Any]]) ?? [] {
            if let name = header["name"] as? String, let value = header["value"] as? String { request.setValue(value, forHTTPHeaderField: name) }
        }
        if let text = body["body"] as? String { request.httpBody = Data(text.utf8) }
        let filename = (body["filename"] as? String).map { ($0 as NSString).lastPathComponent }
        guard let download = await host.download(request, filename: filename, inProfile: profileID) else { throw ExtensionBridge.Failure.invalidRequest }
        let id = nextDownloadID
        nextDownloadID += 1
        let tracked = TrackedDownload(id: id, extensionID: extensionID, download: download, startTime: .now)
        downloads[extensionID, default: [:]][id] = tracked
        deliver("downloads.onCreated", [tracked.item], to: extensionID)
        watch(tracked)
        return id
    }

    /// Reports each change of state or name as `downloads.onChanged`, as Chrome does, until the download ends.
    private func watch(_ tracked: TrackedDownload) {
        withObservationTracking {
            _ = tracked.changeableFields
        } onChange: { [weak self] in
            Task { @MainActor in self?.downloadDidChange(tracked) }
        }
    }

    private func downloadDidChange(_ tracked: TrackedDownload) {
        guard downloads[tracked.extensionID]?[tracked.id] === tracked else { return }
        let previous = tracked.reportedFields
        let current = tracked.changeableFields
        tracked.reportedFields = current
        var delta: [String: Any] = ["id": tracked.id]
        for (key, value) in current where "\(value)" != "\(previous[key] ?? NSNull())" {
            delta[key] = ["previous": previous[key] ?? NSNull(), "current": value]
        }
        if delta.count > 1 { deliver("downloads.onChanged", [delta], to: tracked.extensionID) }
        if tracked.download.state == .inProgress { watch(tracked) }
    }

    func downloadItems(of extensionID: String, matching query: [String: Any]) -> [[String: Any]] {
        (downloads[extensionID] ?? [:]).values.sorted { $0.id < $1.id }.map(\.item).filter { item in
            ["id", "state", "url", "filename"].allSatisfy { key in
                query[key].map { "\($0)" == "\(item[key] ?? NSNull())" } ?? true
            }
        }
    }

    func eraseDownloads(of extensionID: String, matching query: [String: Any]) -> [Int] {
        let erased = downloadItems(of: extensionID, matching: query).compactMap { $0["id"] as? Int }
        for id in erased {
            downloads[extensionID]?[id] = nil
            deliver("downloads.onErased", [id], to: extensionID)
        }
        return erased
    }

}

/// A download an extension started, with the number Chrome's API gives it.
@MainActor
final class TrackedDownload {
    let id: Int
    let extensionID: String
    let download: ExtensionDownload
    let startTime: Date
    /// The fields as last reported, which changes are told against.
    var reportedFields: [String: Any] = [:]

    init(id: Int, extensionID: String, download: ExtensionDownload, startTime: Date) {
        self.id = id
        self.extensionID = extensionID
        self.download = download
        self.startTime = startTime
        reportedFields = changeableFields
    }

    /// The fields `downloads.onChanged` reports.
    var changeableFields: [String: Any] {
        ["state": download.state.rawValue, "filename": download.destination?.path ?? "", "totalBytes": download.totalBytes ?? -1,
         "exists": download.destination.map { FileManager.default.fileExists(atPath: $0.path) } ?? false]
    }

    /// Chrome's `DownloadItem`.
    var item: [String: Any] {
        [
            "id": id, "url": download.sourceURL?.absoluteString ?? "", "finalUrl": download.sourceURL?.absoluteString ?? "",
            "filename": download.destination?.path ?? "", "state": download.state.rawValue, "paused": false, "canResume": false,
            "danger": "safe", "mime": "", "incognito": false, "startTime": startTime.ISO8601Format(), "bytesReceived": download.receivedBytes,
            "totalBytes": download.totalBytes ?? -1, "fileSize": download.totalBytes ?? -1,
            "exists": download.destination.map { FileManager.default.fileExists(atPath: $0.path) } ?? false, "byExtensionId": extensionID
        ]
    }
}
