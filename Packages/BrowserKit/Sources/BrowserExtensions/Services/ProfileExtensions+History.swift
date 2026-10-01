import BrowserCore
import Foundation

extension ProfileExtensions {
    func historyRequest(_ action: String, _ body: [String: Any]) async throws -> Any? {
        guard let host else { throw CancellationError() }
        func date(_ key: String, default fallback: Date? = nil) throws -> Date {
            guard let value = body[key] else {
                if let fallback { return fallback }
                throw ExtensionBridge.Failure.invalidRequest
            }
            guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(), number.doubleValue.isFinite else {
                throw ExtensionBridge.Failure.invalidRequest
            }
            return Date(timeIntervalSince1970: number.doubleValue / 1000)
        }
        func url() throws -> URL {
            guard let text = body["url"] as? String, let url = URL(string: text), NavigationInput.isWebURL(url),
                  url.user == nil, url.password == nil else { throw ExtensionBridge.Failure.invalidRequest }
            return url
        }
        switch action {
        case "search":
            guard let text = body["text"] as? String else { throw ExtensionBridge.Failure.invalidRequest }
            if let value = body["maxResults"] {
                guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                      number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
                      number.doubleValue >= 0, number.doubleValue < Double(Int.max) else { throw ExtensionBridge.Failure.invalidRequest }
            }
            let limit = (body["maxResults"] as? NSNumber)?.intValue ?? 100
            guard limit >= 0 else { throw ExtensionBridge.Failure.invalidRequest }
            let start = try date("startTime", default: .now.addingTimeInterval(-86400)), end = try date("endTime", default: .distantFuture)
            guard start <= end else { throw ExtensionBridge.Failure.invalidRequest }
            return try await host.historyEntries(inProfile: profileID, text: text, since: start, until: end, limit: limit).map(Self.historyItem)
        case "visits":
            return try await host.historyVisits(to: url(), inProfile: profileID).map { visit in
                ["id": String(visit.pageID), "visitId": String(visit.id), "visitTime": visit.date.timeIntervalSince1970 * 1000,
                 "referringVisitId": visit.referringVisitID.map(String.init) ?? "0", "transition": visit.transition.rawValue, "isLocal": true] as [String: Any]
            }
        case "add":
            try await host.addHistoryURL(url(), inProfile: profileID)
        case "deleteURL":
            try await host.removeHistoryURL(url(), inProfile: profileID)
        case "deleteRange":
            let start = try date("startTime"), end = try date("endTime")
            guard start <= end else { throw ExtensionBridge.Failure.invalidRequest }
            try await host.removeHistory(inProfile: profileID, from: start, through: end)
        case "deleteAll":
            try await host.removeHistory(inProfile: profileID, from: nil, through: nil)
        default: throw ExtensionBridge.Failure.unknownRequest
        }
        return nil
    }

    func topSites() async throws -> [[String: Any]] {
        guard let host else { throw CancellationError() }
        return try await host.topSites(inProfile: profileID).map { ["url": $0.url.absoluteString, "title": $0.title] }
    }

    static func historyItem(_ entry: HistoryEntry) -> [String: Any] {
        ["id": String(entry.id), "url": entry.url.absoluteString, "title": entry.title,
         "lastVisitTime": entry.lastVisit.timeIntervalSince1970 * 1000, "visitCount": entry.visitCount]
    }

    public func historyDidVisit(_ entry: HistoryEntry) {
        for id in contexts.keys where providedGrants[id]?.contains("history") == true { deliver("history.onVisited", [Self.historyItem(entry)], to: id) }
    }

    public func historyDidRemove(_ urls: [URL], all: Bool) {
        for id in contexts.keys where providedGrants[id]?.contains("history") == true {
            deliver("history.onVisitRemoved", [["allHistory": all, "urls": urls.map(\.absoluteString)]], to: id)
        }
    }
}
