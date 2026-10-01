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
        case "search": return try downloadItems(of: extensionID, matching: body)
        case "cancel": try tracked().download.cancel()
        case "show": host?.revealDownloads(try tracked().download.destination)
        case "showFolder": host?.revealDownloads(nil)
        case "erase": return try eraseDownloads(of: extensionID, matching: body)
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

    /// Chrome's `DownloadQuery`: exact fields, ranges, regular expressions, search terms, order and limit.
    func downloadItems(of extensionID: String, matching query: [String: Any]) throws -> [[String: Any]] {
        let tracked = (downloads[extensionID] ?? [:]).values.sorted { $0.id < $1.id }
        var matches: [(TrackedDownload, [String: Any])] = []
        for download in tracked {
            let item = download.item
            if try DownloadQuery.matches(item, download: download, query: query) { matches.append((download, item)) }
        }
        for key in ((query["orderBy"] as? [String]) ?? ["-startTime"]).reversed() {
            let descending = key.hasPrefix("-"), field = descending ? String(key.dropFirst()) : key
            guard TrackedDownload.fields.contains(field) else { throw DownloadQuery.Failure.unsupported("orderBy \(field)") }
            matches = matches.enumerated().sorted { lhs, rhs in
                let order = DownloadQuery.compare(lhs.element.1[field], rhs.element.1[field])
                if order == .orderedSame { return lhs.offset < rhs.offset }
                return descending ? order == .orderedDescending : order == .orderedAscending
            }.map(\.element)
        }
        let limit = (query["limit"] as? Int).flatMap { $0 > 0 ? $0 : nil } ?? matches.count
        return matches.prefix(limit).map(\.1)
    }

    func eraseDownloads(of extensionID: String, matching query: [String: Any]) throws -> [Int] {
        let erased = try downloadItems(of: extensionID, matching: query).compactMap { $0["id"] as? Int }
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

    /// The fields of Chrome's `DownloadItem` Aero reports. Aero has no pause and no danger check beyond Gatekeeper's
    /// quarantine, so a download is never paused and has no known danger.
    static let fields: Set = ["id", "url", "finalUrl", "filename", "state", "paused", "canResume", "danger", "mime", "incognito",
                              "startTime", "endTime", "bytesReceived", "totalBytes", "fileSize", "exists", "byExtensionId", "error"]

    /// Chrome's `DownloadItem`.
    var item: [String: Any] {
        var item: [String: Any] = [
            "id": id, "url": download.sourceURL?.absoluteString ?? "", "finalUrl": (download.finalURL ?? download.sourceURL)?.absoluteString ?? "",
            "filename": download.destination?.path ?? "", "state": download.state.rawValue, "paused": false, "canResume": download.canResume,
            "danger": "safe", "mime": download.mimeType ?? "", "incognito": false, "startTime": startTime.ISO8601Format(),
            "bytesReceived": download.receivedBytes, "totalBytes": download.totalBytes ?? -1, "fileSize": download.totalBytes ?? -1,
            "exists": download.destination.map { FileManager.default.fileExists(atPath: $0.path) } ?? false, "byExtensionId": extensionID
        ]
        if let end = download.endTime { item["endTime"] = end.ISO8601Format() }
        if download.state == .interrupted { item["error"] = "NETWORK_FAILED" }
        return item
    }
}

/// Matching for `downloads.search` and `downloads.erase`.
@MainActor
enum DownloadQuery {
    enum Failure: LocalizedError {
        case unsupported(String)
        var errorDescription: String? {
            switch self { case .unsupported(let what): "\(what) is not supported in Aero's downloads.search." }
        }
    }

    private static let controls: Set = ["limit", "orderBy"]

    static func matches(_ item: [String: Any], download: TrackedDownload, query: [String: Any]) throws -> Bool {
        for (key, value) in query where !(value is NSNull) && !controls.contains(key) {
            switch key {
            case "query":
                let haystack = "\(item["url"] ?? "") \(item["finalUrl"] ?? "") \(item["filename"] ?? "")".lowercased()
                for term in (value as? [String]) ?? [] where !term.isEmpty {
                    let excluded = term.hasPrefix("-"), word = (excluded ? String(term.dropFirst()) : term).lowercased()
                    if haystack.contains(word) == excluded { return false }
                }
            case "startedBefore", "startedAfter", "endedBefore", "endedAfter":
                guard let bound = date(value) else { return false }
                let field = key.hasPrefix("started") ? download.startTime : download.download.endTime
                guard let field else { return false }
                if key.hasSuffix("Before") ? field >= bound : field <= bound { return false }
            case "totalBytesGreater", "totalBytesLess":
                guard let bound = value as? Int64 ?? (value as? Int).map(Int64.init), let total = download.download.totalBytes else { return false }
                if key.hasSuffix("Greater") ? total <= bound : total >= bound { return false }
            case "filenameRegex", "urlRegex", "finalUrlRegex":
                guard let pattern = value as? String else { return false }
                let field = key == "filenameRegex" ? "filename" : key == "urlRegex" ? "url" : "finalUrl"
                let regex = try NSRegularExpression(pattern: pattern)
                let text = item[field] as? String ?? ""
                if regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil { return false }
            case let field where TrackedDownload.fields.contains(field):
                if field.hasSuffix("Time") {
                    guard let wanted = date(value), let actual = (item[field] as? String).flatMap(date), wanted == actual else { return false }
                } else if "\(value)" != "\(item[field] ?? NSNull())" {
                    return false
                }
            default:
                throw Failure.unsupported(key)
            }
        }
        return true
    }

    /// Chrome takes ISO 8601 strings or milliseconds since 1970.
    static func date(_ value: Any) -> Date? {
        if let text = value as? String { return try? Date(text, strategy: .iso8601) }
        if let milliseconds = value as? Double { return Date(timeIntervalSince1970: milliseconds / 1000) }
        if let milliseconds = value as? Int { return Date(timeIntervalSince1970: Double(milliseconds) / 1000) }
        return nil
    }

    static func compare(_ lhs: Any?, _ rhs: Any?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (l as Int, r as Int): l < r ? .orderedAscending : l > r ? .orderedDescending : .orderedSame
        case let (l as Int64, r as Int64): l < r ? .orderedAscending : l > r ? .orderedDescending : .orderedSame
        case let (l as Bool, r as Bool): l == r ? .orderedSame : l ? .orderedDescending : .orderedAscending
        default: "\(lhs ?? "")".compare("\(rhs ?? "")")
        }
    }
}
