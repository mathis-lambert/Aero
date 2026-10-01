import AppKit
import BrowserCore
import Foundation
import Observation
import os
import WebKit

/// Owns one profile's controller, loaded contexts and runtime resources.
@MainActor @Observable
public final class ProfileExtensions: NSObject {
    static let logger = Logger(subsystem: Diagnostics.subsystem, category: Diagnostics.Category.extensions)

    @ObservationIgnored let controller: WKWebExtensionController
    @ObservationIgnored private let bridge = ExtensionBridge()
    public private(set) var contexts: [String: WKWebExtensionContext] = [:]
    /// Changes when a button's icon, badge or label does, so the chrome redraws them.
    public internal(set) var actionRevision = 0
    /// Changes when an extension's errors or commands do.
    public private(set) var statusRevision = 0
    /// The desktop app each extension last reached, or failed to reach, through native messaging.
    public internal(set) var desktopApps: [String: DesktopAppConnection] = [:]

    @ObservationIgnored let profileID: UUID
    @ObservationIgnored private let folder: URL
    @ObservationIgnored let nativeHostFolders: [URL]
    @ObservationIgnored weak var registry: ExtensionRegistry?
    @ObservationIgnored let idle: IdleMonitor
    var host: ExtensionHost? { registry?.host }

    /// Grants for permissions implemented by Aero rather than WebKit.
    @ObservationIgnored var providedGrants: [String: Set<String>] = [:]
    @ObservationIgnored var nativeSessions: [String: [NativeSession]] = [:]
    @ObservationIgnored lazy var mainWindow = MainWindowAdapter(owner: self)
    @ObservationIgnored var tabs: [UUID: BrowserTabAdapter] = [:]
    @ObservationIgnored var windows: [ExtensionWindow] = []
    @ObservationIgnored var authentication: [String: [UUID: ExtensionAuthentication]] = [:]
    @ObservationIgnored let offscreen = OffscreenDocuments()
    @ObservationIgnored let power = ExtensionPower()
    @ObservationIgnored var speech: ExtensionSpeech?

    @ObservationIgnored let events = ExtensionEvents()
    /// WebKit's popovers presented for actions, which WebKit loads and sizes to their page.
    @ObservationIgnored var popups: [String: (action: WKWebExtension.Action, popover: NSPopover)] = [:]
    /// The options of each extension's notifications on screen, which updates change.
    @ObservationIgnored var notifications: [String: [String: [String: Any]]] = [:]
    @ObservationIgnored var downloads: [String: [Int: TrackedDownload]] = [:]
    @ObservationIgnored var nextDownloadID = 1
    @ObservationIgnored var idleIntervals: [String: Int] = [:]
    @ObservationIgnored var idleStates: [String: IdleMonitor.State] = [:]
    @ObservationIgnored private var observers: [String: [any NSObjectProtocol]] = [:]
    /// Manifest defaults retained for restoring customized commands.
    @ObservationIgnored private var declaredShortcuts: [String: [String: (key: String?, modifiers: NSEvent.ModifierFlags)]] = [:]

    init(profileID: UUID, folder: URL, nativeHostFolders: [URL], store: WKWebsiteDataStore, ephemeral: Bool,
         idle: IdleMonitor, registry: ExtensionRegistry) {
        let configuration: WKWebExtensionController.Configuration = ephemeral ? .nonPersistent() : .init(identifier: profileID)
        configuration.defaultWebsiteDataStore = store
        let views = WKWebViewConfiguration()
        views.websiteDataStore = store
        // Extensions tell browsers apart by their user agent, as pages do.
        views.applicationNameForUserAgent = BrowserIdentity.applicationNameForUserAgent
        views.setURLSchemeHandler(bridge, forURLScheme: ExtensionBridge.scheme)
        configuration.webViewConfiguration = views
        controller = WKWebExtensionController(configuration: configuration)
        self.profileID = profileID
        self.folder = folder
        self.nativeHostFolders = nativeHostFolders
        self.idle = idle
        self.registry = registry
        super.init()
        bridge.owner = self
        controller.delegate = self
    }

    /// Ends everything the profile's extensions run, when the profile goes. Best effort: the profile goes regardless,
    /// and its packages and data are removed after.
    func close() {
        for id in Array(contexts.keys) { try? unload(id) }
        controller.delegate = nil
    }

    // MARK: - Installation

    /// A candidate has its own immutable directory, never the active extension's path.
    @MainActor
    public struct Candidate {
        public let identifier: String
        public let packageID: UUID
        public let webExtension: WKWebExtension
        /// What the person is asked to accept: WebKit's permissions and those Aero provides.
        public var permissions: [String] { ExtensionCapabilities.requestedPermissions(of: webExtension) }
        public var sites: [String] { webExtension.allRequestedMatchPatterns.map(\.string).sorted() }
        public var unavailableFeatures: [ExtensionFeature] { ExtensionCapabilities.unavailableFeatures(of: webExtension.manifest) }
        /// It runs in every website, so it may fill the profile's passwords in place of Aero.
        public var fillsWebsites: Bool { ExtensionCapabilities.fillsWebsites(webExtension) }
        /// It is a password manager, which fills the profile's passwords unless the person says otherwise.
        public var managesPasswords: Bool { ExtensionCapabilities.managesPasswords(webExtension) }
    }

    public func prepare(crx: Data, identifier: String) async throws -> Candidate {
        let packageID = UUID()
        let destination = packageFolder(packageID)
        try await Task.detached(priority: .userInitiated) {
            try ExtensionPackage.install(.archive(ExtensionPackage.archive(ofCRX: crx, identifier: identifier)), at: destination)
        }.value
        return Candidate(identifier: identifier, packageID: packageID, webExtension: try await WKWebExtension(resourceBaseURL: destination))
    }

    public func prepare(folder source: URL) async throws -> Candidate {
        let packageID = UUID()
        let destination = packageFolder(packageID)
        let identifier = try await Task.detached(priority: .userInitiated) {
            let identifier = ExtensionPackage.identifier(ofFolder: source)
            try ExtensionPackage.install(.folder(source), at: destination)
            return identifier
        }.value
        return Candidate(identifier: identifier, packageID: packageID, webExtension: try await WKWebExtension(resourceBaseURL: destination))
    }

    public func discard(_ candidate: Candidate) async throws {
        let directory = packageFolder(candidate.packageID)
        try await Task.detached { try FileManager.default.removeItem(at: directory) }.value
    }

    func packageFolder(_ id: UUID) -> URL { folder.appendingPathComponent(id.uuidString, isDirectory: true) }

    /// A persisted uninstall intent remains until runtime storage and package cleanup finish.
    public func remove(_ record: InstalledExtension) async throws {
        try unload(record.id)
        // Unloading destroys session storage. WebKit cannot measure it on an unloaded context.
        let types: Set<WKWebExtension.DataType> = [.local, .synchronized]
        let records = await controller.dataRecords(ofTypes: types).filter { $0.uniqueIdentifier == record.id }
        for data in records { if let error = data.errors.first { throw error } }
        await controller.removeData(ofTypes: types, from: records)
        for data in records { if let error = data.errors.first { throw error } }
        // Keep the package until registry removal commits; launch cleanup removes it afterwards.
    }

    // MARK: - Loading

    /// Loads a prepared package with saved grants and the current compatibility layer. Its stable ID identifies storage.
    public func load(_ record: InstalledExtension) async throws {
        try unload(record.id)
        let package = packageFolder(record.packageID)
        try await Task.detached(priority: .userInitiated) { try ExtensionPackage.refreshCompatibility(in: package) }.value
        let webExtension = try await WKWebExtension(resourceBaseURL: package)
        let context = WKWebExtensionContext(for: webExtension)
        context.uniqueIdentifier = record.id
        guard let origin = URL(string: "chrome-extension://\(record.id)/") else { throw ExtensionBridge.Failure.invalidRequest }
        context.baseURL = origin
        #if DEBUG
        context.isInspectable = true
        #endif
        context.grantedPermissions = Dictionary(uniqueKeysWithValues: record.grantedPermissions.map { (WKWebExtension.Permission($0), Date.distantFuture) })
        try ExtensionSiteAccess.restore(record.grantedSites, on: context)
        providedGrants[record.id] = Set(record.grantedPermissions).intersection(ExtensionCapabilities.providedPermissions)
        observe(context, id: record.id)
        // The context reads the open tabs from the window the delegate returns.
        do { try controller.load(context) }
        catch {
            stopObserving(record.id)
            throw error
        }
        contexts[record.id] = context
        declaredShortcuts[record.id] = Dictionary(uniqueKeysWithValues: context.commands.map { ($0.id, ($0.activationKey, $0.modifierFlags)) })
        statusRevision += 1
    }

    public func unload(_ extensionID: String) throws {
        guard let context = contexts[extensionID] else { return }
        try controller.unload(context)
        contexts.removeValue(forKey: extensionID)
        declaredShortcuts[extensionID] = nil
        stopObserving(extensionID)
        revoke(ExtensionCapabilities.providedPermissions, of: extensionID)
        providedGrants[extensionID] = nil
        for session in nativeSessions.removeValue(forKey: extensionID) ?? [] { session.connection.close() }
        desktopApps[extensionID] = nil
        events.drop(extensionID)
        closePopup(of: extensionID)
        for window in windows where window.extensionID == extensionID { window.close() }
        statusRevision += 1
    }

    private func observe(_ context: WKWebExtensionContext, id: String) {
        let center = NotificationCenter.default
        let changed: @Sendable (Notification) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.statusRevision += 1 } }
        observers[id] = [
            center.addObserver(forName: WKWebExtensionContext.errorsDidUpdateNotification, object: context, queue: .main, using: changed),
            center.addObserver(forName: WKWebExtensionContext.grantedPermissionsWereRemovedNotification, object: context, queue: .main) { [weak self] note in
                let removed = (note.userInfo?[WKWebExtensionContext.NotificationUserInfoKey.permissions] as? Set<WKWebExtension.Permission>) ?? []
                MainActor.assumeIsolated { self?.didRemove(permissions: Set(removed.map(\.rawValue)), sites: [], from: id) }
            },
            center.addObserver(forName: WKWebExtensionContext.grantedPermissionMatchPatternsWereRemovedNotification, object: context, queue: .main) { [weak self] note in
                let removed = (note.userInfo?[WKWebExtensionContext.NotificationUserInfoKey.matchPatterns] as? Set<WKWebExtension.MatchPattern>) ?? []
                MainActor.assumeIsolated { self?.didRemove(permissions: [], sites: Set(removed.map(\.string)), from: id) }
            }
        ]
    }

    private func stopObserving(_ id: String) {
        for observer in observers.removeValue(forKey: id) ?? [] { NotificationCenter.default.removeObserver(observer) }
    }

    /// An extension gave up what it was granted, with `permissions.remove`; its saved grants follow.
    private func didRemove(permissions: Set<String>, sites: Set<String>, from extensionID: String) {
        guard contexts[extensionID] != nil, !(permissions.isEmpty && sites.isEmpty) else { return }
        host?.extensionDidRemovePermissions(permissions, sites: sites, of: extensionID, inProfile: profileID)
    }

    // MARK: - Status

    public func status(of extensionID: String) -> ExtensionStatus? {
        let _ = statusRevision
        guard let context = contexts[extensionID] else { return nil }
        return ExtensionStatus(context: context)
    }

    // MARK: - Buttons

    /// The extension's button for the selected tab.
    public func action(for extensionID: String) -> WKWebExtension.Action? {
        contexts[extensionID]?.action(for: host?.selectedTabID(inProfile: profileID).map(tab))
    }

    /// Runs the extension's action for the selected tab. WebKit loads and sizes the popup page, if the action has
    /// one, then asks for it to be presented. The button closes a popup that shows.
    public func performAction(for extensionID: String) {
        guard let context = contexts[extensionID] else { return }
        if let popup = popups[extensionID], popup.popover.isShown {
            closePopup(of: extensionID)
            return
        }
        let selected = host?.selectedTabID(inProfile: profileID).map(tab)
        if let selected { context.userGesturePerformed(in: selected) }
        context.performAction(for: selected)
    }

    /// Shows WebKit's popover for the action, one at a time.
    func presentPopup(_ action: WKWebExtension.Action, context: WKWebExtensionContext) {
        for id in popups.keys where id != context.uniqueIdentifier { closePopup(of: id) }
        guard let popover = action.popupPopover else { return }
        popover.behavior = .transient
        popups[context.uniqueIdentifier] = (action, popover)
        action.hasUnreadBadgeText = false
        host?.presentPopup(popover, for: context.uniqueIdentifier, inProfile: profileID)
    }

    /// Closing WebKit's popover lets WebKit unload the page; the next popup loads the current popup page.
    func closePopup(of extensionID: String) {
        guard let popup = popups.removeValue(forKey: extensionID) else { return }
        popup.popover.close()
        popup.action.closePopup()
    }

    // MARK: - Commands

    public func commands(of extensionID: String) -> [WKWebExtension.Command] {
        let _ = statusRevision
        return contexts[extensionID]?.commands ?? []
    }

    /// Gives a command another shortcut, or none; the app keeps the person's choices and applies them after loading.
    public func setShortcut(_ key: String?, modifiers: NSEvent.ModifierFlags, forCommand identifier: String, of extensionID: String) {
        guard let command = contexts[extensionID]?.commands.first(where: { $0.id == identifier }) else { return }
        command.activationKey = key
        command.modifierFlags = modifiers
        statusRevision += 1
    }

    public func restoreShortcut(forCommand identifier: String, of extensionID: String) {
        guard let declared = declaredShortcuts[extensionID]?[identifier] else { return }
        setShortcut(declared.key, modifiers: declared.modifiers, forCommand: identifier, of: extensionID)
    }

    /// Runs a matching command only when the app allows its binding.
    public func perform(_ event: NSEvent, allowed: (WKWebExtension.Command) -> Bool) -> Bool {
        for context in contexts.values {
            guard let command = context.command(for: event), allowed(command) else { continue }
            if command.id == "_execute_action" || command.id == "_execute_browser_action" {
                performAction(for: context.uniqueIdentifier)
                return true
            }
            context.performCommand(command)
            return true
        }
        return false
    }

    // MARK: - Context menus

    func menuItems(forTab tabID: UUID) -> [NSMenuItem] {
        let adapter = tab(tabID)
        return contexts.values
            .sorted { ($0.webExtension.displayName ?? "") < ($1.webExtension.displayName ?? "") }
            .flatMap { $0.menuItems(for: adapter) }
    }

    // MARK: - Tab events

    public func didOpenTab(_ tabID: UUID) { controller.didOpenTab(tab(tabID)) }

    public func didCloseTab(_ tabID: UUID) {
        guard let closed = tabs.removeValue(forKey: tabID) else { return }
        controller.didCloseTab(closed, windowIsClosing: false)
    }

    public func didActivateTab(_ tabID: UUID, previous: UUID?) {
        controller.didActivateTab(tab(tabID), previousActiveTab: previous.map(tab))
        controller.didSelectTabs([tab(tabID)])
        if let previous { controller.didDeselectTabs([tab(previous)]) }
    }

    public func didChangeTab(_ tabID: UUID, properties: WKWebExtension.TabChangedProperties) {
        controller.didChangeTabProperties(properties, for: tab(tabID))
    }

    public func didMoveTab(_ tabID: UUID, fromIndex index: Int) {
        controller.didMoveTab(tab(tabID), from: index, in: mainWindow)
    }

    func tab(_ tabID: UUID) -> BrowserTabAdapter {
        if let existing = tabs[tabID] { return existing }
        let created = BrowserTabAdapter(id: tabID, owner: self)
        tabs[tabID] = created
        return created
    }

    /// The window extensions consider focused changed: the main window, one of theirs, or none.
    func focusDidChange() {
        guard NSApplication.shared.isActive, let key = NSApplication.shared.keyWindow else { controller.didFocusWindow(nil); return }
        if key === host?.mainWindow { controller.didFocusWindow(mainWindow) }
        else if let window = windows.first(where: { $0.window === key }) { controller.didFocusWindow(window) }
    }
}
