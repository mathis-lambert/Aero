import AppKit
import BrowserCore
import Foundation
import Observation
import WebKit

/// What extensions see of the browser: one window with the profile's tabs, and what they may ask of
/// them. Every call names a tab the host may no longer have; it then answers `nil` or does nothing.
@MainActor
public protocol WebExtensionHost: AnyObject {
    func tabIDs(inProfile profileID: UUID) -> [UUID]
    func selectedTabID(inProfile profileID: UUID) -> UUID?
    func tab(_ tabID: UUID) -> BrowserTab?
    func openTab(_ url: URL, inProfile profileID: UUID, selected: Bool) -> UUID?
    func activate(tabID: UUID)
    func close(tabID: UUID)
    var windowFrame: CGRect { get }
    /// Whether the person grants an extension what it asks for beyond its installation.
    func requestPermissions(_ permissions: Set<String>, sites: Set<String>, for extensionID: String) async -> Bool
    func presentPopup(_ popover: NSPopover, for extensionID: String)
}

/// A profile's extensions: one controller, persistent under the profile's identifier, with the
/// profile's website data store. See docs/EXTENSIONS.md.
@MainActor @Observable
public final class ProfileExtensions: NSObject, WKWebExtensionControllerDelegate {
    @ObservationIgnored public let controller: WKWebExtensionController
    public private(set) var contexts: [String: WKWebExtensionContext] = [:]
    /// Changes when a button's icon, badge or label does, so the chrome redraws them.
    public private(set) var actionRevision = 0
    @ObservationIgnored private let profileID: UUID
    /// The profile's prepared extensions, one folder each.
    @ObservationIgnored private let folder: URL
    @ObservationIgnored private weak var host: WebExtensionHost?
    @ObservationIgnored private let pages: (UUID) -> BrowserPage?
    @ObservationIgnored private lazy var window = ExtensionWindow(owner: self)
    @ObservationIgnored private var tabs: [UUID: ExtensionTab] = [:]

    init(profileID: UUID, folder: URL, store: WKWebsiteDataStore, ephemeral: Bool, host: WebExtensionHost?, pages: @escaping (UUID) -> BrowserPage?) {
        let configuration: WKWebExtensionController.Configuration = ephemeral ? .nonPersistent() : .init(identifier: profileID)
        configuration.defaultWebsiteDataStore = store
        let views = WKWebViewConfiguration()
        // Extensions tell browsers apart by their user agent, as pages do.
        views.applicationNameForUserAgent = BrowserPage.userAgentName
        configuration.webViewConfiguration = views
        controller = WKWebExtensionController(configuration: configuration)
        self.profileID = profileID
        self.folder = folder
        self.host = host
        self.pages = pages
        super.init()
        controller.delegate = self
    }

    // MARK: - Installation

    /// What a Chrome Web Store package asks for, read from its checked archive without installing it.
    public func inspect(crx: Data, identifier: String) async throws -> WKWebExtension {
        let archive = FileManager.default.temporaryDirectory.appendingPathComponent("aero-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: archive) }
        try ExtensionPackage.archive(ofCRX: crx, identifier: identifier).write(to: archive)
        return try await WKWebExtension(resourceBaseURL: archive)
    }

    /// Checks a Chrome Web Store package and prepares it, for the person to review before it is loaded.
    public func prepare(crx: Data, identifier: String) async throws -> WKWebExtension {
        let destination = folder.appendingPathComponent(identifier, isDirectory: true)
        try await Task.detached(priority: .userInitiated) {
            try ExtensionPackage.install(archive: ExtensionPackage.archive(ofCRX: crx, identifier: identifier), at: destination)
        }.value
        return try await WKWebExtension(resourceBaseURL: destination)
    }

    /// Copies and prepares an unpacked extension; its identifier comes from the folder's path, as in Chrome.
    public func prepare(folder source: URL) async throws -> (identifier: String, extension: WKWebExtension) {
        let identifier = ExtensionPackage.identifier(forPublicKey: Data(source.standardizedFileURL.path.utf8))
        let destination = folder.appendingPathComponent(identifier, isDirectory: true)
        try await Task.detached(priority: .userInitiated) { try ExtensionPackage.install(folder: source, at: destination) }.value
        return (identifier, try await WKWebExtension(resourceBaseURL: destination))
    }

    /// Unloads the extension and deletes its files and its storage, as uninstalling does in Chrome.
    public func remove(_ extensionID: String) async {
        let types: Set<WKWebExtension.DataType> = [.local, .session, .synchronized]
        if let context = contexts[extensionID], let record = await controller.dataRecord(ofTypes: types, for: context) {
            await controller.removeData(ofTypes: types, from: [record])
        }
        unload(extensionID)
        // Best effort: files left behind are replaced by the next installation of the same extension.
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(extensionID, isDirectory: true))
    }

    /// Loads a prepared extension with the permissions the person granted. The identifier names its storage,
    /// so it must stay the same across launches.
    @discardableResult
    public func load(_ record: InstalledExtension) async throws -> WKWebExtension {
        unload(record.id)
        let webExtension = try await WKWebExtension(resourceBaseURL: folder.appendingPathComponent(record.id, isDirectory: true))
        let context = WKWebExtensionContext(for: webExtension)
        context.uniqueIdentifier = record.id
        #if DEBUG
        context.isInspectable = true
        #endif
        for permission in record.grantedPermissions { context.setPermissionStatus(.grantedExplicitly, for: WKWebExtension.Permission(permission)) }
        for site in record.grantedSites {
            if let pattern = try? WKWebExtension.MatchPattern(string: site) { context.setPermissionStatus(.grantedExplicitly, for: pattern) }
        }
        // The context reads the open tabs from the window the delegate returns.
        try controller.load(context)
        contexts[record.id] = context
        return webExtension
    }

    public func unload(_ extensionID: String) {
        guard let context = contexts.removeValue(forKey: extensionID) else { return }
        try? controller.unload(context)
    }

    /// The configuration an extension's own page, such as its options, needs to load in a tab.
    func configuration(for url: URL) -> WKWebViewConfiguration? {
        contexts.values.first { url.host() == $0.baseURL.host() }?.webViewConfiguration
    }

    // MARK: - Buttons

    /// The extension's button for the selected tab.
    public func action(for extensionID: String) -> WKWebExtension.Action? {
        contexts[extensionID]?.action(for: host?.selectedTabID(inProfile: profileID).map(tab))
    }

    /// Runs the extension's action, or opens its popup, for the selected tab.
    public func performAction(for extensionID: String) {
        contexts[extensionID]?.performAction(for: host?.selectedTabID(inProfile: profileID).map(tab))
    }

    public func webExtensionController(_ controller: WKWebExtensionController, didUpdate action: WKWebExtension.Action,
                                       forExtensionContext context: WKWebExtensionContext) {
        actionRevision += 1
    }

    // MARK: - Tab events

    public func didOpenTab(_ tabID: UUID) { controller.didOpenTab(tab(tabID)) }

    public func didCloseTab(_ tabID: UUID) {
        guard let closed = tabs.removeValue(forKey: tabID) else { return }
        controller.didCloseTab(closed, windowIsClosing: false)
    }

    public func didActivateTab(_ tabID: UUID, previous: UUID?) {
        controller.didActivateTab(tab(tabID), previousActiveTab: previous.map(tab))
    }

    public func didUpdateTab(_ tabID: UUID) { controller.didChangeTabProperties([.URL, .title], for: tab(tabID)) }

    private func tab(_ tabID: UUID) -> ExtensionTab {
        if let existing = tabs[tabID] { return existing }
        let created = ExtensionTab(id: tabID, owner: self)
        tabs[tabID] = created
        return created
    }

    // MARK: - WKWebExtensionControllerDelegate

    public func webExtensionController(_ controller: WKWebExtensionController, openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        [window]
    }

    public func webExtensionController(_ controller: WKWebExtensionController, focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        window
    }

    public func webExtensionController(_ controller: WKWebExtensionController, openNewTabUsing configuration: WKWebExtension.TabConfiguration,
                                       for extensionContext: WKWebExtensionContext) async throws -> (any WKWebExtensionTab)? {
        guard let url = configuration.url, let tabID = host?.openTab(url, inProfile: profileID, selected: configuration.shouldBeActive) else { return nil }
        return tab(tabID)
    }

    public func webExtensionController(_ controller: WKWebExtensionController, openOptionsPageFor extensionContext: WKWebExtensionContext) async throws {
        guard let url = extensionContext.optionsPageURL else { return }
        _ = host?.openTab(url, inProfile: profileID, selected: true)
    }

    public func webExtensionController(_ controller: WKWebExtensionController, promptForPermissions permissions: Set<WKWebExtension.Permission>,
                                       in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext) async -> (Set<WKWebExtension.Permission>, Date?) {
        let granted = await host?.requestPermissions(Set(permissions.map(\.rawValue)), sites: [], for: extensionContext.uniqueIdentifier) == true
        return (granted ? permissions : [], nil)
    }

    public func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
                                       in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext) async -> (Set<WKWebExtension.MatchPattern>, Date?) {
        let granted = await host?.requestPermissions([], sites: Set(matchPatterns.map(\.string)), for: extensionContext.uniqueIdentifier) == true
        return (granted ? matchPatterns : [], nil)
    }

    public func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionToAccess urls: Set<URL>,
                                       in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext) async -> (Set<URL>, Date?) {
        let granted = await host?.requestPermissions([], sites: Set(urls.compactMap { $0.host() }), for: extensionContext.uniqueIdentifier) == true
        return (granted ? urls : [], nil)
    }

    public func webExtensionController(_ controller: WKWebExtensionController, presentActionPopup action: WKWebExtension.Action,
                                       for context: WKWebExtensionContext) async throws {
        guard let popover = action.popupPopover else { return }
        host?.presentPopup(popover, for: context.uniqueIdentifier)
    }

    // MARK: - Tabs and the window, as WebKit sees them

    fileprivate final class ExtensionTab: NSObject, WKWebExtensionTab {
        let id: UUID
        unowned let owner: ProfileExtensions

        init(id: UUID, owner: ProfileExtensions) {
            self.id = id
            self.owner = owner
        }

        func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { owner.window }
        func indexInWindow(for context: WKWebExtensionContext) -> Int { owner.host?.tabIDs(inProfile: owner.profileID).firstIndex(of: id) ?? NSNotFound }
        func title(for context: WKWebExtensionContext) -> String? { owner.host?.tab(id)?.title }
        func url(for context: WKWebExtensionContext) -> URL? { owner.host?.tab(id)?.url }
        func isPinned(for context: WKWebExtensionContext) -> Bool { owner.host?.tab(id)?.isPinned == true }
        func isSelected(for context: WKWebExtensionContext) -> Bool { owner.host?.selectedTabID(inProfile: owner.profileID) == id }
        /// A hibernated tab has no view; WebKit then reports it without one.
        func webView(for context: WKWebExtensionContext) -> WKWebView? { owner.pages(id)?.webView }
        func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { owner.pages(id)?.isLoading != true }

        func activate(for context: WKWebExtensionContext) async throws { owner.host?.activate(tabID: id) }
        func close(for context: WKWebExtensionContext) async throws { owner.host?.close(tabID: id) }
        func loadURL(_ url: URL, for context: WKWebExtensionContext) async throws { owner.pages(id)?.load(url) }
        func reload(fromOrigin: Bool, for context: WKWebExtensionContext) async throws { owner.pages(id)?.reload() }
    }

    fileprivate final class ExtensionWindow: NSObject, WKWebExtensionWindow {
        unowned let owner: ProfileExtensions

        init(owner: ProfileExtensions) { self.owner = owner }

        func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] {
            (owner.host?.tabIDs(inProfile: owner.profileID) ?? []).map(owner.tab)
        }

        func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
            owner.host?.selectedTabID(inProfile: owner.profileID).map(owner.tab)
        }

        func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType { .normal }
        func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState { .normal }
        func isPrivate(for context: WKWebExtensionContext) -> Bool { false }
        func frame(for context: WKWebExtensionContext) -> CGRect { owner.host?.windowFrame ?? .null }
    }
}
