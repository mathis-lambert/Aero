import AppKit
import BrowserCore
import WebKit

/// App integration for profile-scoped extensions. Requests for deleted tabs or profiles must have no effect.
@MainActor
public protocol ExtensionHost: AnyObject {
    // MARK: Tabs

    /// The profile's tabs in the main window, in sidebar order across its spaces.
    func tabIDs(inProfile profileID: UUID) -> [UUID]
    /// The selected tab, while one of the profile's spaces is shown.
    func selectedTabID(inProfile profileID: UUID) -> UUID?
    func tab(_ tabID: UUID) -> BrowserTab?
    /// The tab's view while its page is loaded; hibernated tabs have none.
    func webView(forTab tabID: UUID) -> WKWebView?
    func openTab(_ url: URL, inProfile profileID: UUID, selected: Bool) -> UUID?
    /// Shows the New Tab page in one of the profile's spaces, as a window opened without addresses does.
    func showNewTab(inProfile profileID: UUID)
    /// Selects the tab, switching to its space.
    func activateTab(_ tabID: UUID)
    func removeTab(_ tabID: UUID)
    func copyTab(_ tabID: UUID) -> UUID?
    func load(_ url: URL, inTab tabID: UUID)
    func reloadTab(_ tabID: UUID, fromOrigin: Bool)
    func goBack(inTab tabID: UUID)
    func goForward(inTab tabID: UUID)
    /// Favorites are Aero's pinned tabs.
    func setPinned(_ pinned: Bool, tab tabID: UUID)
    func setZoom(_ factor: Double, tab tabID: UUID)

    // MARK: Windows and pages

    var mainWindow: NSWindow? { get }
    /// A configuration for a website page of the profile, with its data store and extensions, such as one an
    /// extension opens in a window of its own.
    func websiteConfiguration(forProfile profileID: UUID) -> WKWebViewConfiguration
    /// Shows an extension's popup, anchored to its button when it shows.
    func presentPopup(_ popover: NSPopover, for extensionID: String, inProfile profileID: UUID)

    // MARK: Permissions and removal

    /// Whether the person grants what an extension asks for beyond its installation. A grant is saved before this
    /// returns `true`.
    func requestPermissions(_ permissions: Set<String>, sites: Set<String>, for extensionID: String, inProfile profileID: UUID) async -> Bool
    /// The extension gave up permissions; the saved grants follow.
    func extensionDidRemovePermissions(_ permissions: Set<String>, sites: Set<String>, of extensionID: String, inProfile profileID: UUID)
    /// An extension asked to remove `extensionID`, itself or another; the person confirms, then the host removes it.
    func extensionRequestsRemoval(_ extensionID: String, by requester: String, inProfile profileID: UUID)
    /// An extension asked to turn another on or off. Returns whether the person accepted and the change was made.
    func extensionRequestsEnabling(_ extensionID: String, _ enabled: Bool, by requester: String, inProfile profileID: UUID) async -> Bool
    /// The profile's saved registrations, for `management`.
    func installedExtensions(inProfile profileID: UUID) -> [InstalledExtension]
    func installedExtension(_ extensionID: String, inProfile profileID: UUID) -> InstalledExtension?

    // MARK: Passwords

    /// The extension filling the profile's passwords in place of Aero, or `nil` for Aero.
    func passwordExtension(inProfile profileID: UUID) -> String?
    /// Whether Aero offers to save passwords while it fills them.
    var offersToSavePasswords: Bool { get }
    /// Lets the extension fill the profile's passwords, or gives them back to Aero with `nil`.
    func setPasswordExtension(_ extensionID: String?, inProfile profileID: UUID)

    // MARK: Chrome Web Store

    /// Aero's install button for the store page of `extensionID`.
    func webStoreButton(for extensionID: String, inProfile profileID: UUID) -> WebStoreButton
    /// Returns once the installation it started was answered.
    func installFromWebStore(_ extensionID: String, inProfile profileID: UUID) async

    // MARK: System services

    /// Shows a notification from an extension; `identifier` is unique within the extension.
    func showNotification(_ notification: ExtensionNotification) async throws
    func removeNotification(_ identifier: String, of extensionID: String, inProfile profileID: UUID)
    /// The identifiers of the extension's notifications macOS still shows.
    func shownNotifications(of extensionID: String, inProfile profileID: UUID) async -> Set<String>
    /// Whether the system lets Aero show notifications; not yet asked counts as allowed, as it asks on the first one.
    func notificationsAllowed() async -> Bool
    /// Starts a download an extension asked for, listed with the others, using the profile's website data.
    func download(_ request: URLRequest, filename: String?, inProfile profileID: UUID) async -> ExtensionDownload?
    func revealDownloads(_ file: URL?)
    /// Uses Aero's chosen provider; extension text is always a search query, never a navigation address.
    func searchURL(for text: String, inProfile profileID: UUID) -> URL?

    // MARK: History

    func historyEntries(inProfile profileID: UUID, text: String, since start: Date, until end: Date, limit: Int) async throws -> [HistoryEntry]
    func historyVisits(to url: URL, inProfile profileID: UUID) async throws -> [HistoryVisit]
    func addHistoryURL(_ url: URL, inProfile profileID: UUID) async throws
    func removeHistoryURL(_ url: URL, inProfile profileID: UUID) async throws
    func removeHistory(inProfile profileID: UUID, from start: Date?, through end: Date?) async throws
    func topSites(inProfile profileID: UUID) async throws -> [HistoryEntry]
}

/// A notification an extension shows, as the system presents it.
public struct ExtensionNotification: Sendable {
    public let identifier: String
    public let extensionID: String
    public let profileID: UUID
    public let extensionName: String
    public let title: String
    public let message: String
    /// A file of the extension's package.
    public let image: URL?
    public let buttons: [String]
}

/// A download an extension started, as the host tracks it.
@MainActor
public protocol ExtensionDownload: AnyObject {
    var sourceURL: URL? { get }
    /// The address the server answered from, after redirects.
    var finalURL: URL? { get }
    var mimeType: String? { get }
    var destination: URL? { get }
    var endTime: Date? { get }
    var canResume: Bool { get }
    var state: ExtensionDownloadState { get }
    var receivedBytes: Int64 { get }
    var totalBytes: Int64? { get }
    func cancel()
}

public enum ExtensionDownloadState: String, Sendable {
    case inProgress = "in_progress", interrupted, complete
}
