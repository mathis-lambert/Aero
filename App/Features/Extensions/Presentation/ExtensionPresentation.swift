import BrowserCore
import BrowserExtensions
import Foundation
import WebKit

extension ExtensionFeature {
    var title: String {
        switch self {
        case .sidePanel: String(localized: "Side panel")
        case .accountSignIn: String(localized: "Signing in with a browser account")
        case .blockingRequests: String(localized: "Blocking web requests")
        case .pageOverrides: String(localized: "Replacing the History or Bookmarks page")
        case .bookmarks: String(localized: "Bookmarks and reading list")
        case .tabGroups: String(localized: "Tab groups and recently closed tabs")
        case .proxy: String(localized: "Proxy settings")
        case .speechEngine: String(localized: "Providing voices for text to speech")
        case .capture: String(localized: "Capturing tabs, pages or the screen")
        case .debugger: String(localized: "Debugging pages")
        case .siteSettings: String(localized: "Browser settings")
        case .browsingData: String(localized: "Clearing browsing data")
        case .addressBarKeyword: String(localized: "Address bar keywords")
        case .pushMessaging: String(localized: "Push messages")
        }
    }
}

/// Permissions affecting user data or system access. Internal features such as storage and alarms need no warning.
enum ExtensionPermissionWarning {
    static func warnings(for permissions: [String]) -> [String] {
        var seen = Set<String>()
        return permissions.compactMap(warning).filter { seen.insert($0).inserted }
    }

    private static func warning(_ permission: String) -> String? {
        switch permission {
        case "tabs", "webNavigation", "topSites": String(localized: "Read your browsing history")
        case "history": String(localized: "Read and change your browsing history")
        case "nativeMessaging": String(localized: "Communicate with apps on this Mac")
        case "notifications": String(localized: "Show notifications")
        case "downloads": String(localized: "Manage your downloads")
        case "management": String(localized: "Manage your other extensions")
        case "privacy": String(localized: "Fill your passwords in place of Aero")
        case "clipboardRead": String(localized: "Read what you copy")
        case "clipboardWrite": String(localized: "Change what you copy")
        case "declarativeNetRequest", "declarativeNetRequestWithHostAccess": String(localized: "Block content on pages")
        case "geolocation": String(localized: "Know your location")
        case "cookies": String(localized: "Read and change cookies")
        default: nil
        }
    }
}

/// Shared wording for the installation review and granted site access.
enum ExtensionSiteWarning {
    @MainActor static func warning(for sites: [String]) -> String {
        if sites.isEmpty { return String(localized: "No website, unless you click its button") }
        if sites.contains(where: { (try? WKWebExtension.MatchPattern(string: $0))?.matchesAllHosts == true }) { return String(localized: "Read and change your data on every website") }
        return String(localized: "Read and change your data on \(sites.formatted(.list(type: .and)))")
    }
}

extension DesktopAppConnection {
    func summary(appName: String) -> String {
        switch state {
        case .connected: String(localized: "Connected to \(appName)")
        case .ended: String(localized: "\(appName) closed the connection")
        case .refused(.notInstalled): String(localized: "\(appName) browser integration was not found")
        case .refused(.notAllowed): String(localized: "\(appName) does not accept Aero yet")
        case .refused(.failedToStart): String(localized: "\(appName) could not be started")
        case .refused(.noPermission): String(localized: "The extension may not talk to apps on this Mac")
        }
    }

    var isConnected: Bool { state == .connected }
}
