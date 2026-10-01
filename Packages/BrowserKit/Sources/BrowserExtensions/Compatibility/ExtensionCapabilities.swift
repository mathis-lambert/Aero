import Foundation
import WebKit

/// Something an extension may declare that neither WebKit nor Aero provides. The app names each for the person.
public enum ExtensionFeature: String, CaseIterable, Sendable {
    case sidePanel, accountSignIn, blockingRequests, developerTools, pageOverrides, bookmarks, tabGroups, proxy, speechEngine,
         capture, debugger, siteSettings, browsingData, addressBarKeyword, pushMessaging
}

/// What an extension's manifest asks for, against what WebKit's engine and Aero's compatibility layer provide.
/// See docs/EXTENSIONS.md › Limits.
enum ExtensionCapabilities {
    /// Permissions WebKit does not know and Aero's compatibility layer implements.
    static let providedPermissions: Set<String> = ["offscreen", "idle", "notifications", "downloads", "clipboardRead", "identity", "identity.email", "search", "history", "topSites", "power", "tts", "management", "privacy"]
    static let nativePermissions = Set([
        WKWebExtension.Permission.activeTab, .alarms, .clipboardWrite, .contextMenus, .cookies, .declarativeNetRequest,
        .declarativeNetRequestFeedback, .declarativeNetRequestWithHostAccess, .menus, .nativeMessaging, .scripting,
        .storage, .tabs, .unlimitedStorage, .webNavigation, .webRequest
    ].map(\.rawValue))

    /// What the person accepts at installation: the permissions WebKit recognizes and those Aero provides.
    @MainActor
    static func requestedPermissions(of webExtension: WKWebExtension) -> [String] {
        let declared = Set(strings(webExtension.manifest["permissions"]))
        return Set(webExtension.requestedPermissions.map(\.rawValue)).union(declared.intersection(providedPermissions)).sorted()
    }

    /// Permissions Aero provides that the extension requires, which it cannot give up.
    @MainActor
    static func requiredProvidedPermissions(of webExtension: WKWebExtension) -> Set<String> {
        Set(strings(webExtension.manifest["permissions"])).intersection(providedPermissions)
    }

    /// An extension that runs in every website may fill their forms.
    @MainActor
    static func fillsWebsites(_ webExtension: WKWebExtension) -> Bool {
        webExtension.hasInjectedContent && webExtension.allRequestedMatchPatterns.contains(where: \.matchesAllHosts)
    }

    /// A password manager, by Chrome's contract: it declares `privacy`, through which it turns off the browser's own
    /// password saving (`privacy.services.passwordSavingEnabled`).
    @MainActor
    static func managesPasswords(_ webExtension: WKWebExtension) -> Bool {
        fillsWebsites(webExtension) && Set(strings(webExtension.manifest["permissions"]) + strings(webExtension.manifest["optional_permissions"])).contains("privacy")
    }

    /// Optional permissions Aero provides, which an extension may request later.
    @MainActor
    static func optionalProvidedPermissions(of webExtension: WKWebExtension) -> Set<String> {
        Set(strings(webExtension.manifest["optional_permissions"])).intersection(providedPermissions)
    }

    /// Declared permissions and keys with no implementation in Aero, required or optional: the extension runs without
    /// those parts.
    static func unavailableFeatures(of manifest: [String: Any]) -> [ExtensionFeature] {
        let permissions = Set(strings(manifest["permissions"]) + strings(manifest["optional_permissions"]))
        var features = Set<ExtensionFeature>()
        for (permission, feature) in permissionFeatures where permissions.contains(permission) { features.insert(feature) }
        for (key, feature) in keyFeatures where manifest[key] != nil { features.insert(feature) }
        return ExtensionFeature.allCases.filter(features.contains)
    }

    private static let permissionFeatures: [String: ExtensionFeature] = [
        "sidePanel": .sidePanel, "webRequestBlocking": .blockingRequests,
        "bookmarks": .bookmarks, "sessions": .tabGroups, "tabGroups": .tabGroups,
        "proxy": .proxy, "ttsEngine": .speechEngine, "tabCapture": .capture, "desktopCapture": .capture, "pageCapture": .capture,
        "debugger": .debugger, "contentSettings": .siteSettings, "fontSettings": .siteSettings, "browsingData": .browsingData,
        "gcm": .pushMessaging, "readingList": .bookmarks
    ]

    private static let keyFeatures: [String: ExtensionFeature] = [
        "side_panel": .sidePanel, "devtools_page": .developerTools, "chrome_url_overrides": .pageOverrides, "omnibox": .addressBarKeyword,
        "tts_engine": .speechEngine, "oauth2": .accountSignIn
    ]

    private static func strings(_ value: Any?) -> [String] { (value as? [Any])?.compactMap { $0 as? String } ?? [] }
}
