import AppKit
import BrowserCore
import WebKit
@testable import BrowserExtensions

/// Holds the tabs and registrations a test gives it and records what extensions ask.
@MainActor
final class TestHost: ExtensionHost {
    var records: [InstalledExtension] = []
    var removalRequests: [String] = []
    var removedPermissions: [String: Set<String>] = [:]
    var browserTabs: [BrowserTab] = []
    var selectedTabID: UUID?
    var mainWindow: NSWindow?
    var openedURLs: [URL] = []
    /// Loaded pages of tabs, by tab.
    var views: [UUID: WKWebView] = [:]
    /// What the person answers when an extension asks for more.
    var grantsPermissions = false
    var permissionRequests: [(permissions: Set<String>, sites: Set<String>)] = []
    var enablingRequests: [(id: String, enabled: Bool)] = []

    func tabIDs(inProfile profileID: UUID) -> [UUID] { browserTabs.map(\.id) }
    func selectedTabID(inProfile profileID: UUID) -> UUID? { selectedTabID }
    func tab(_ tabID: UUID) -> BrowserTab? { browserTabs.first { $0.id == tabID } }
    func webView(forTab tabID: UUID) -> WKWebView? { views[tabID] }
    func openTab(_ url: URL, inProfile profileID: UUID, selected: Bool) -> UUID? {
        openedURLs.append(url)
        let tab = BrowserTab(spaceID: browserTabs.first?.spaceID ?? UUID(), url: url)
        browserTabs.append(tab)
        if selected { selectedTabID = tab.id }
        return tab.id
    }
    var newTabRequests = 0
    func showNewTab(inProfile profileID: UUID) { newTabRequests += 1 }
    func activateTab(_ tabID: UUID) {}
    func removeTab(_ tabID: UUID) {}
    func copyTab(_ tabID: UUID) -> UUID? { nil }
    func load(_ url: URL, inTab tabID: UUID) {}
    func reloadTab(_ tabID: UUID, fromOrigin: Bool) {}
    func goBack(inTab tabID: UUID) {}
    func goForward(inTab tabID: UUID) {}
    func setPinned(_ pinned: Bool, tab tabID: UUID) {}
    func setZoom(_ factor: Double, tab tabID: UUID) {}
    func websiteConfiguration(forProfile profileID: UUID) -> WKWebViewConfiguration { WKWebViewConfiguration() }
    func presentPopup(_ popover: NSPopover, for extensionID: String, inProfile profileID: UUID) {
        guard let anchor = mainWindow?.contentView else { return }
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }
    func requestPermissions(_ permissions: Set<String>, sites: Set<String>, for extensionID: String, inProfile profileID: UUID) async -> Bool {
        permissionRequests.append((permissions, sites))
        return grantsPermissions
    }
    func extensionDidRemovePermissions(_ permissions: Set<String>, sites: Set<String>, of extensionID: String, inProfile profileID: UUID) {
        removedPermissions[extensionID, default: []].formUnion(permissions)
    }
    func extensionRequestsRemoval(_ extensionID: String, by requester: String, inProfile profileID: UUID) { removalRequests.append(extensionID) }
    func extensionRequestsEnabling(_ extensionID: String, _ enabled: Bool, by requester: String, inProfile profileID: UUID) async -> Bool {
        enablingRequests.append((extensionID, enabled))
        return false
    }
    func installedExtensions(inProfile profileID: UUID) -> [InstalledExtension] { records }
    func installedExtension(_ extensionID: String, inProfile profileID: UUID) -> InstalledExtension? { records.first { $0.id == extensionID } }
    func webStoreButton(for extensionID: String, inProfile profileID: UUID) -> WebStoreButton { WebStoreButton(title: "", isEnabled: false) }
    func installFromWebStore(_ extensionID: String, inProfile profileID: UUID) async {}
    func showNotification(_ notification: ExtensionNotification) async throws {}
    func removeNotification(_ identifier: String, of extensionID: String, inProfile profileID: UUID) {}
    func shownNotifications(of extensionID: String, inProfile profileID: UUID) async -> Set<String> { [] }
    func notificationsAllowed() async -> Bool { true }
    var passwordExtension: String?
    let offersToSavePasswords = true
    func passwordExtension(inProfile profileID: UUID) -> String? { passwordExtension }
    func setPasswordExtension(_ extensionID: String?, inProfile profileID: UUID) { passwordExtension = extensionID }
    func download(_ request: URLRequest, filename: String?, inProfile profileID: UUID) async -> ExtensionDownload? { nil }
    func revealDownloads(_ file: URL?) {}
    func searchURL(for text: String, inProfile profileID: UUID) -> URL? { nil }
    func historyEntries(inProfile profileID: UUID, text: String, since start: Date, until end: Date, limit: Int) async throws -> [HistoryEntry] { [] }
    func historyVisits(to url: URL, inProfile profileID: UUID) async throws -> [HistoryVisit] { [] }
    func addHistoryURL(_ url: URL, inProfile profileID: UUID) async throws {}
    func removeHistoryURL(_ url: URL, inProfile profileID: UUID) async throws {}
    func removeHistory(inProfile profileID: UUID, from start: Date?, through end: Date?) async throws {}
    func topSites(inProfile profileID: UUID) async throws -> [HistoryEntry] { [] }
}
