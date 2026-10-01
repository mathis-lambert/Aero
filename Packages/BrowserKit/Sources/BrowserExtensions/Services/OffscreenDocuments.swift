import Foundation
import WebKit

/// One hidden page per extension for DOM work. Closing or unloading the extension releases it.
@MainActor
final class OffscreenDocuments {
    enum Failure: LocalizedError {
        case alreadyOpen, notOpen, notExtensionPage

        var errorDescription: String? {
            switch self {
            case .alreadyOpen: "Only a single offscreen document may be created."
            case .notOpen: "No current offscreen document."
            case .notExtensionPage: "The offscreen document must be one of the extension's own pages."
            }
        }
    }

    private var documents: [String: WKWebView] = [:]

    func create(_ url: URL, for context: WKWebExtensionContext) throws {
        let extensionID = context.uniqueIdentifier
        guard documents[extensionID] == nil else { throw Failure.alreadyOpen }
        guard url.scheme == context.baseURL.scheme, url.host() == context.baseURL.host(), let configuration = context.webViewConfiguration else {
            throw Failure.notExtensionPage
        }
        let view = WKWebView(frame: .zero, configuration: configuration)
        #if DEBUG
        view.isInspectable = true
        #endif
        view.load(URLRequest(url: url))
        documents[extensionID] = view
    }

    func close(for extensionID: String) {
        guard let view = documents.removeValue(forKey: extensionID) else { return }
        view.stopLoading()
    }

    func closeOpen(for extensionID: String) throws {
        guard documents[extensionID] != nil else { throw Failure.notOpen }
        close(for: extensionID)
    }

    func url(for extensionID: String) -> URL? { documents[extensionID]?.url }
    func hasDocument(for extensionID: String) -> Bool { documents[extensionID] != nil }
}

extension ProfileExtensions {
    private static let offscreenReasons: Set = ["TESTING", "AUDIO_PLAYBACK", "IFRAME_SCRIPTING", "DOM_SCRAPING", "BLOBS", "DOM_PARSER",
                                                "USER_MEDIA", "DISPLAY_MEDIA", "WEB_RTC", "CLIPBOARD", "LOCAL_STORAGE", "WORKERS",
                                                "BATTERY_STATUS", "MATCH_MEDIA", "GEOLOCATION"]

    func offscreenRequest(_ action: String, _ body: [String: Any], context: WKWebExtensionContext) throws -> Any? {
        let extensionID = context.uniqueIdentifier
        try require("offscreen", of: extensionID)
        switch action {
        case "create":
            guard let url = (body["url"] as? String).flatMap(URL.init(string:)), let reasons = body["reasons"] as? [String], !reasons.isEmpty,
                  Set(reasons).isSubset(of: Self.offscreenReasons), body["justification"] is String else { throw ExtensionBridge.Failure.invalidRequest }
            try offscreen.create(url, for: context)
            return nil
        case "close":
            try offscreen.closeOpen(for: extensionID)
            return nil
        case "has":
            return offscreen.hasDocument(for: extensionID)
        default:
            throw ExtensionBridge.Failure.unknownRequest
        }
    }
}
