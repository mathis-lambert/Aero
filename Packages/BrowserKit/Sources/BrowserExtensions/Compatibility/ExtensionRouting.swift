import AppKit
import BrowserCore
import Foundation
import WebKit

/// Routes the compatibility layer's requests to the service that owns them, attributed to the calling context.
extension ProfileExtensions {
    func handle(_ route: String, _ body: [String: Any], context: WKWebExtensionContext, caller: WKWebView) async throws -> Any? {
        let extensionID = context.uniqueIdentifier
        guard contexts[extensionID] === context else { throw CancellationError() }
        let parts = route.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { throw ExtensionBridge.Failure.unknownRequest }
        let (service, action) = (parts[0], parts[1])
        switch service {
        case "tts": return try speechRequest(action, body, of: extensionID)
        case "power": return try powerRequest(action, body, of: extensionID)
        case "history":
            try require("history", of: extensionID)
            return try await historyRequest(action, body)
        case "topSites" where action == "get":
            try require("topSites", of: extensionID)
            return try await topSites()
        case "identity": return try await identityRequest(action, body, context: context)
        case "permissions": return try await permissionsRequest(action, body, context: context)
        case "management": return try await managementRequest(action, body, context: context)
        case "notifications": return try await notificationsRequest(action, body, context: context)
        case "downloads":
            try require("downloads", of: extensionID)
            return try await downloadsRequest(action, body, of: extensionID)
        case "privacy": return try privacyRequest(action, body, context: context)
        case "offscreen": return try offscreenRequest(action, body, context: context)
        case "idle": return try idleRequest(action, body, of: extensionID)
        case "clipboard": return try clipboardRequest(action, body, context: context)
        case "search" where action == "url":
            try require("search", of: extensionID)
            guard let text = body["text"] as? String, let url = host?.searchURL(for: text, inProfile: profileID) else { throw ExtensionBridge.Failure.invalidRequest }
            return url.absoluteString
        case "events" where action == "next":
            return await nextEvents(Set((body["events"] as? [String]) ?? []), for: context, from: caller)
        case "tabs" where action == "inPopup":
            return popups[extensionID].map { $0.action.popupWebView === caller } ?? false
        case "runtime" where action == "contexts":
            return contextInfo(of: context, matching: body)
        default:
            throw ExtensionBridge.Failure.unknownRequest
        }
    }

    func require(_ permission: String, of extensionID: String) throws {
        guard providedGrants[extensionID]?.contains(permission) == true else { throw ExtensionBridge.Failure.notAllowed(permission) }
    }
}
