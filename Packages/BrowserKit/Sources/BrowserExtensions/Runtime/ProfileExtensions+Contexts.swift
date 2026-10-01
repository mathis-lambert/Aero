import Foundation
import WebKit

extension ProfileExtensions {
    /// `runtime.getContexts`: the extension's background, offscreen document, open popup, and its pages in tabs and
    /// windows. A tab is named by its place (`tab`); the layer turns that into WebKit's tab and window identifiers.
    /// The background is listed while it may run: WebKit starts it on demand and does not say when it stops.
    func contextInfo(of context: WKWebExtensionContext, matching filter: [String: Any]) -> [[String: Any]] {
        let extensionID = context.uniqueIdentifier
        let origin = context.baseURL.absoluteString.hasSuffix("/") ? String(context.baseURL.absoluteString.dropLast()) : context.baseURL.absoluteString
        func info(_ type: String, _ id: String, _ url: URL?, frameID: Int = 0, tab: [String: Int]? = nil) -> [String: Any] {
            var item: [String: Any] = ["contextType": type, "contextId": id, "documentUrl": url?.absoluteString ?? NSNull(),
                                       "documentOrigin": origin, "frameId": frameID, "tabId": -1, "windowId": -1, "incognito": false]
            if let tab { item["tab"] = tab }
            return item
        }
        guard filter["incognito"] as? Bool != true else { return [] }
        var found: [[String: Any]] = []
        if context.webExtension.hasBackgroundContent {
            let background = context.webExtension.manifest["background"] as? [String: Any]
            let path = (background?["service_worker"] as? String) ?? (background?["page"] as? String)
            found.append(info("BACKGROUND", "background-\(extensionID)", path.flatMap { URL(string: $0, relativeTo: context.baseURL)?.absoluteURL }, frameID: -1))
        }
        if let url = offscreen.url(for: extensionID) { found.append(info("OFFSCREEN_DOCUMENT", "offscreen-\(extensionID)", url)) }
        if let popup = popups[extensionID], popup.popover.isShown {
            found.append(info("POPUP", "popup-\(extensionID)", popup.action.popupWebView?.url))
        }
        for (index, tabID) in (host?.tabIDs(inProfile: profileID) ?? []).enumerated() {
            guard let url = host?.tab(tabID)?.url, url.host() == context.baseURL.host() else { continue }
            found.append(info("TAB", tabID.uuidString, url, tab: ["index": index]))
        }
        for (index, window) in windows.enumerated() where window.extensionID == extensionID {
            found.append(info("TAB", window.id.uuidString, window.webView.url, tab: ["window": index, "index": 0]))
        }
        let fields = ["contextTypes": "contextType", "contextIds": "contextId", "documentUrls": "documentUrl", "documentOrigins": "documentOrigin",
                      "frameIds": "frameId"]
        return found.filter { item in
            fields.allSatisfy { key, field in
                guard let wanted = filter[key] as? [Any] else { return true }
                return item[field].map { value in wanted.contains { "\($0)" == "\(value)" } } ?? false
            }
        }
    }
}
