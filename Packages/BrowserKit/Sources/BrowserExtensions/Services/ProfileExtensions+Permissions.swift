import BrowserCore
import Foundation
import WebKit

/// `permissions` for requests that include a permission Aero provides. WebKit answers the rest itself.
extension ProfileExtensions {
    enum PermissionFailure: LocalizedError {
        case notDeclared, required

        var errorDescription: String? {
            switch self {
            case .notDeclared: "Only permissions specified in the manifest may be requested."
            case .required: "You cannot remove required permissions."
            }
        }
    }

    func permissionsRequest(_ action: String, _ body: [String: Any], context: WKWebExtensionContext) async throws -> Any? {
        let extensionID = context.uniqueIdentifier
        switch action {
        case "provided":
            return (providedGrants[extensionID] ?? []).sorted()
        case "request":
            return try await request(permissions: strings(body["permissions"]), origins: strings(body["origins"]), for: context)
        case "remove":
            let removed = Set(try strings(body["permissions"]))
            guard removed.isSubset(of: ExtensionCapabilities.providedPermissions) else { throw ExtensionBridge.Failure.invalidRequest }
            guard removed.isDisjoint(with: ExtensionCapabilities.requiredProvidedPermissions(of: context.webExtension)) else { throw PermissionFailure.required }
            let granted = removed.intersection(providedGrants[extensionID] ?? [])
            guard !granted.isEmpty else { return true }
            revoke(granted, of: extensionID)
            host?.extensionDidRemovePermissions(granted, sites: [], of: extensionID, inProfile: profileID)
            deliver("permissions.onRemoved", [["permissions": granted.sorted(), "origins": [String]()]], to: extensionID)
            return true
        default:
            throw ExtensionBridge.Failure.unknownRequest
        }
    }

    private func strings(_ value: Any?) throws -> [String] {
        guard let value else { return [] }
        guard let list = value as? [String] else { throw ExtensionBridge.Failure.invalidRequest }
        return list
    }

    /// Asks once for everything missing, as Chrome does, and grants all of it or nothing. WebKit's own permissions and
    /// sites are granted on the context, which reports them to the extension; Aero reports its own.
    private func request(permissions: [String], origins: [String], for context: WKWebExtensionContext) async throws -> Bool {
        let extensionID = context.uniqueIdentifier
        let webExtension = context.webExtension
        let provided = Set(permissions).intersection(ExtensionCapabilities.providedPermissions)
        let native = Set(permissions).subtracting(provided).map { WKWebExtension.Permission(rawValue: $0) }
        let patterns = try origins.map { origin -> WKWebExtension.MatchPattern in
            guard let pattern = try? WKWebExtension.MatchPattern(string: origin), ExtensionSiteAccess.permits(pattern) else {
                throw ExtensionBridge.Failure.invalidRequest
            }
            return pattern
        }
        let missingProvided = provided.subtracting(providedGrants[extensionID] ?? [])
        let missingNative = native.filter { !context.hasPermission($0) }
        let missingPatterns = patterns.filter { context.permissionStatus(for: $0) != .grantedExplicitly && context.permissionStatus(for: $0) != .grantedImplicitly }
        guard missingProvided.isSubset(of: ExtensionCapabilities.optionalProvidedPermissions(of: webExtension)),
              missingNative.allSatisfy(webExtension.optionalPermissions.contains),
              missingPatterns.allSatisfy({ pattern in webExtension.optionalPermissionMatchPatterns.contains { $0.matches(pattern) } }) else {
            throw PermissionFailure.notDeclared
        }
        guard !(missingProvided.isEmpty && missingNative.isEmpty && missingPatterns.isEmpty) else { return true }
        let asked = missingProvided.union(missingNative.map { $0.rawValue })
        let sites = Set(missingPatterns.map { $0.string })
        let granted = await host?.requestPermissions(asked, sites: sites, for: extensionID, inProfile: profileID) == true
        guard granted, contexts[extensionID] === context else { return false }
        for permission in missingNative { context.setPermissionStatus(.grantedExplicitly, for: permission) }
        for pattern in missingPatterns { context.setPermissionStatus(.grantedExplicitly, for: pattern) }
        if !missingPatterns.isEmpty { restrictAfterGrant(context) }
        if !missingProvided.isEmpty {
            providedGrants[extensionID, default: []].formUnion(missingProvided)
            deliver("permissions.onAdded", [["permissions": missingProvided.sorted(), "origins": [String]()]], to: extensionID)
        }
        return true
    }

    /// Ends what the permissions allowed: the extension no longer has them, or it is unloading.
    func revoke(_ permissions: Set<String>, of extensionID: String) {
        providedGrants[extensionID]?.subtract(permissions)
        if permissions.contains("power") { power.close(extensionID) }
        if permissions.contains("tts") { closeSpeech(of: extensionID) }
        if permissions.contains("identity") { cancelAuthentication(of: extensionID) }
        if permissions.contains("offscreen") { offscreen.close(for: extensionID) }
        if permissions.contains("idle") {
            idleIntervals[extensionID] = nil
            idleStates[extensionID] = nil
            updateIdleInterest()
        }
        if permissions.contains("notifications") {
            for identifier in (notifications.removeValue(forKey: extensionID) ?? [:]).keys {
                host?.removeNotification(identifier, of: extensionID, inProfile: profileID)
            }
        }
        if permissions.contains("downloads") { downloads[extensionID] = nil }
    }
}
