import BrowserCore
import Foundation
import WebKit

/// `management`: an extension knows itself; with the `management` permission, it knows and manages the profile's
/// other extensions too, each change confirmed by the person.
extension ProfileExtensions {
    /// What the app reports of the profile's extensions, for `management` events.
    public enum ManagementChange: Sendable { case installed, uninstalled, enabled, disabled }

    func managementRequest(_ action: String, _ body: [String: Any], context: WKWebExtensionContext) async throws -> Any? {
        let extensionID = context.uniqueIdentifier
        switch action {
        case "self":
            return try await info(of: extensionID)
        case "uninstallSelf":
            host?.extensionRequestsRemoval(extensionID, by: extensionID, inProfile: profileID)
            return nil
        default:
            break
        }
        try require("management", of: extensionID)
        switch action {
        case "all":
            var items: [[String: Any]] = []
            for record in host?.installedExtensions(inProfile: profileID) ?? [] { items.append(try await info(of: record.id)) }
            return items
        case "get":
            return try await info(of: try target(body))
        case "uninstall":
            host?.extensionRequestsRemoval(try target(body), by: extensionID, inProfile: profileID)
            return nil
        case "setEnabled":
            let target = try target(body)
            guard let enabled = body["enabled"] as? Bool, target != extensionID else { throw ExtensionBridge.Failure.invalidRequest }
            guard await host?.extensionRequestsEnabling(target, enabled, by: extensionID, inProfile: profileID) == true else {
                throw ManagementFailure.declined
            }
            return nil
        default:
            throw ExtensionBridge.Failure.unknownRequest
        }
    }

    enum ManagementFailure: LocalizedError {
        case notInstalled(String), declined

        var errorDescription: String? {
            switch self {
            case .notInstalled(let id): "Failed to find extension with id \(id)."
            case .declined: "The user did not accept the change."
            }
        }
    }

    private func target(_ body: [String: Any]) throws -> String {
        guard let id = body["id"] as? String else { throw ExtensionBridge.Failure.invalidRequest }
        guard host?.installedExtension(id, inProfile: profileID) != nil else { throw ManagementFailure.notInstalled(id) }
        return id
    }

    /// Chrome's `ExtensionInfo`, from the loaded extension, or from its package while it is turned off.
    private func info(of extensionID: String) async throws -> [String: Any] {
        guard let record = host?.installedExtension(extensionID, inProfile: profileID) else { throw ManagementFailure.notInstalled(extensionID) }
        let context = contexts[extensionID]
        let webExtension: WKWebExtension
        if let context { webExtension = context.webExtension }
        else { webExtension = try await WKWebExtension(resourceBaseURL: packageFolder(record.packageID)) }
        let base = "chrome-extension://\(extensionID)/"
        let icons = ((webExtension.manifest["icons"] as? [String: Any]) ?? [:]).compactMap { size, path -> [String: Any]? in
            guard let size = Int(size), let path = path as? String else { return nil }
            return ["size": size, "url": base + path.trimmingPrefix("/")]
        }.sorted { ($0["size"] as? Int ?? 0) < ($1["size"] as? Int ?? 0) }
        let isDevelopment = if case .folder = record.source { true } else { false }
        let permissions = context.map { $0.currentPermissions.map(\.rawValue) + (providedGrants[extensionID] ?? []) } ?? record.grantedPermissions
        let sites = context.map { $0.currentPermissionMatchPatterns.map(\.string) } ?? record.grantedSites
        var info: [String: Any] = [
            "id": extensionID, "name": webExtension.displayName ?? "", "shortName": webExtension.displayShortName ?? "",
            "description": webExtension.displayDescription ?? "", "version": webExtension.version ?? record.version,
            "mayDisable": true, "enabled": record.isEnabled, "isApp": false, "type": "extension",
            "offlineEnabled": webExtension.manifest["offline_enabled"] as? Bool ?? false, "installType": isDevelopment ? "development" : "normal",
            "homepageUrl": (webExtension.manifest["homepage_url"] as? String) ?? "",
            "optionsUrl": (webExtension.manifest["options_ui"] as? [String: Any])?["page"].flatMap { $0 as? String }.map { base + $0 }
                ?? (webExtension.manifest["options_page"] as? String).map { base + $0 } ?? "",
            "permissions": Array(Set(permissions)).sorted(), "hostPermissions": Array(Set(sites)).sorted(), "icons": icons
        ]
        if let versionName = webExtension.displayVersion, versionName != webExtension.version { info["versionName"] = versionName }
        if record.source == .webStore { info["updateUrl"] = "https://clients2.google.com/service/update2/crx" }
        if !record.isEnabled { info["disabledReason"] = "unknown" }
        return info
    }

    /// Reports a change of the profile's extensions to those that may manage them. An uninstalled extension is told
    /// by its identifier, as Chrome does.
    public func managementDidChange(_ change: ManagementChange, of extensionID: String) {
        let listeners = contexts.keys.filter { $0 != extensionID && providedGrants[$0]?.contains("management") == true }
        guard !listeners.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            let argument: Any
            if change == .uninstalled { argument = extensionID }
            else {
                // Best effort: an extension whose package cannot be read is not reported. Delivery skips listeners
                // that unloaded meanwhile.
                guard let info = try? await self.info(of: extensionID) else { return }
                argument = info
            }
            let name = switch change {
            case .installed: "management.onInstalled"
            case .uninstalled: "management.onUninstalled"
            case .enabled: "management.onEnabled"
            case .disabled: "management.onDisabled"
            }
            for id in listeners where self.providedGrants[id]?.contains("management") == true { self.deliver(name, [argument], to: id) }
        }
    }
}
