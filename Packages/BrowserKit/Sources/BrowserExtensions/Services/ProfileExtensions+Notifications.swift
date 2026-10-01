import AppKit
import BrowserCore
import Foundation
import Observation
import WebKit

extension ProfileExtensions {
    // MARK: - Notifications

    func notificationsRequest(_ action: String, _ body: [String: Any], context: WKWebExtensionContext) async throws -> Any? {
        let extensionID = context.uniqueIdentifier
        try require("notifications", of: extensionID)
        switch action {
        case "create", "update":
            return try await showNotification(body, update: action == "update", for: context)
        case "clear":
            guard let identifier = body["id"] as? String else { throw ExtensionBridge.Failure.invalidRequest }
            guard notifications[extensionID]?.removeValue(forKey: identifier) != nil else { return false }
            host?.removeNotification(identifier, of: extensionID, inProfile: profileID)
            return true
        case "all":
            // What macOS still shows: the person or the system may have removed one without a dismissal.
            let shown = await host?.shownNotifications(of: extensionID, inProfile: profileID) ?? []
            notifications[extensionID] = notifications[extensionID]?.filter { shown.contains($0.key) }
            return (notifications[extensionID] ?? [:]).mapValues { _ in true }
        case "permissionLevel":
            return await host?.notificationsAllowed() == false ? "denied" : "granted"
        default:
            throw ExtensionBridge.Failure.unknownRequest
        }
    }

    var listensForNotificationPermission: Bool {
        contexts.keys.contains { events.names(for: $0).contains("notifications.onPermissionLevelChanged") }
    }

    /// The system's answer for Aero changed; extensions that show notifications hear it.
    func notificationsAllowedDidChange(_ allowed: Bool) {
        for id in contexts.keys where providedGrants[id]?.contains("notifications") == true {
            deliver("notifications.onPermissionLevelChanged", [allowed ? "granted" : "denied"], to: id)
        }
    }

    func showNotification(_ body: [String: Any], update: Bool, for context: WKWebExtensionContext) async throws -> Any {
        let extensionID = context.uniqueIdentifier
        let requested = (body["id"] as? String) ?? ""
        let shown = notifications[extensionID]?[requested]
        if update, shown == nil { return false }
        let identifier = requested.isEmpty ? UUID().uuidString : requested
        guard let changes = body["options"] as? [String: Any] else { throw ExtensionBridge.Failure.invalidRequest }
        let options = (shown ?? [:]).merging(changes) { $1 }
        // Chrome requires these to create a notification; an update changes only what it names.
        if !update, ["type", "iconUrl", "title", "message"].contains(where: { options[$0] == nil }) {
            throw NotificationFailure.missingProperty
        }
        let buttons = ((options["buttons"] as? [[String: Any]]) ?? []).compactMap { $0["title"] as? String }
        let notification = ExtensionNotification(
            identifier: identifier, extensionID: extensionID, profileID: profileID, extensionName: context.webExtension.displayName ?? extensionID,
            title: (options["title"] as? String) ?? "", message: (options["message"] as? String) ?? "",
            image: ((options["iconUrl"] as? String) ?? (options["imageUrl"] as? String)).flatMap { packageFile($0, of: context) },
            buttons: Array(buttons.prefix(2)))
        guard let host else { throw ExtensionBridge.Failure.unknownRequest }
        try await host.showNotification(notification)
        notifications[extensionID, default: [:]][identifier] = options
        return update ? true : identifier
    }

    /// A file of the extension's package an address names, never one outside it.
    private func packageFile(_ address: String, of context: WKWebExtensionContext) -> URL? {
        guard let url = URL(string: address, relativeTo: context.baseURL)?.absoluteURL, url.host() == context.baseURL.host(),
              let record = host?.installedExtension(context.uniqueIdentifier, inProfile: profileID) else { return nil }
        let root = packageFolder(record.packageID).standardizedFileURL
        let file = root.appendingPathComponent(url.path).standardizedFileURL
        return file.path.hasPrefix(root.path + "/") ? file : nil
    }

    /// The person clicked a notification, or one of its buttons, or dismissed it.
    public func notification(_ identifier: String, of extensionID: String, didReceive response: NotificationResponse) {
        guard notifications[extensionID]?[identifier] != nil else { return }
        switch response {
        case .clicked: deliver("notifications.onClicked", [identifier], to: extensionID)
        case .button(let index): deliver("notifications.onButtonClicked", [identifier, index], to: extensionID)
        case .dismissed:
            notifications[extensionID]?[identifier] = nil
            deliver("notifications.onClosed", [identifier, true], to: extensionID)
        }
    }

    public enum NotificationResponse: Sendable { case clicked, button(Int), dismissed }

    enum NotificationFailure: LocalizedError {
        case missingProperty
        var errorDescription: String? { "Some of the required properties are missing: type, iconUrl, title and message." }
    }

}

