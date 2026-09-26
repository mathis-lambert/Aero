import BrowserCore
import Foundation
import os
import WebKit

/// Owns live resources. The UI may detach a page without destroying it; idle pages hibernate
/// and are restored from their interaction state when activated again.
@MainActor
public final class WebPageRegistry {
    struct LivePage {
        let page: BrowserPage
        var lastActive: ContinuousClock.Instant
        var lastExemption: ContinuousClock.Instant?
        /// Set for popups: the page whose `window.opener` they may still use.
        var openerTabID: UUID?
    }

    static let signposter = OSSignposter(subsystem: Diagnostics.subsystem, category: Diagnostics.Category.pageLifecycle)

    public var hibernationSettings: HibernationSettings {
        get { policy.settings }
        set { policy.settings = newValue; refreshHibernationSchedule() }
    }
    public weak var delegate: WebPageRegistryDelegate?
    public weak var extensionHost: WebExtensionHost?
    public let downloads: DownloadCoordinator
    private let contentBlocker: ContentBlocker?

    var livePages: [UUID: LivePage] = [:]
    var activeTabID: UUID?
    var policy: HibernationPolicy
    var evaluation: Task<Void, Never>?
    private var hibernatedStates: [UUID: Any] = [:]
    private var stores: [UUID: WKWebsiteDataStore] = [:]
    private var extensions: [UUID: ProfileExtensions] = [:]
    private var pressureMonitor: MemoryPressureMonitor?
    private let ephemeral: Bool
    private let extensionsFolder: URL
    private let nativeHostFolders: [URL]

    /// `nativeHostFolders` are searched for native messaging host manifests, in order.
    public convenience init(downloads: DownloadCoordinator, contentBlocker: ContentBlocker? = nil, extensionsFolder: URL, nativeHostFolders: [URL],
                            ephemeral: Bool, hibernation: HibernationSettings = .default) {
        let limit = HibernationPolicy.liveBackgroundPageLimit(forPhysicalMemory: ProcessInfo.processInfo.physicalMemory)
        self.init(downloads: downloads, contentBlocker: contentBlocker, extensionsFolder: extensionsFolder, nativeHostFolders: nativeHostFolders,
                  ephemeral: ephemeral, hibernation: hibernation, liveBackgroundPageLimit: limit)
    }

    package init(downloads: DownloadCoordinator, contentBlocker: ContentBlocker? = nil, extensionsFolder: URL = FileManager.default.temporaryDirectory,
                 nativeHostFolders: [URL] = [], ephemeral: Bool, hibernation: HibernationSettings, liveBackgroundPageLimit: Int) {
        self.downloads = downloads
        self.extensionsFolder = extensionsFolder
        self.nativeHostFolders = nativeHostFolders
        self.contentBlocker = contentBlocker
        self.ephemeral = ephemeral
        policy = HibernationPolicy(settings: hibernation, liveBackgroundPageLimit: liveBackgroundPageLimit)
        pressureMonitor = MemoryPressureMonitor { [weak self] pressure in
            self?.policy.pressure = pressure
            self?.refreshHibernationSchedule()
        }
        contentBlocker?.onInstall = { [weak self] in self?.refreshContentBlocking() }
    }

    isolated deinit { evaluation?.cancel() }

    public func dataStore(for profileID: UUID) -> WKWebsiteDataStore {
        if let store = stores[profileID] { return store }
        let store = ephemeral ? WKWebsiteDataStore.nonPersistent() : WKWebsiteDataStore(forIdentifier: profileID)
        stores[profileID] = store
        return store
    }

    /// Made with the profile's first page, so every page of the profile runs its extensions.
    public func extensions(for profileID: UUID) -> ProfileExtensions {
        if let existing = extensions[profileID] { return existing }
        let created = ProfileExtensions(profileID: profileID, folder: extensionsFolder.appendingPathComponent(profileID.uuidString, isDirectory: true),
                                        nativeHostFolders: nativeHostFolders, store: dataStore(for: profileID), ephemeral: ephemeral, host: extensionHost) { [weak self] in
            self?.livePages[$0]?.page
        }
        extensions[profileID] = created
        return created
    }

    /// The profile's extensions if they were made, for views and tab events, which must not make them.
    public func extensionsIfMade(for profileID: UUID) -> ProfileExtensions? { extensions[profileID] }


    /// Makes the tab's page visible, creating or restoring it when needed.
    public func activate(_ tab: BrowserTab, profileID: UUID) -> BrowserPage {
        leave(activeTabID, for: tab.id)
        markPreviousActiveAsIdle()
        activeTabID = tab.id
        let page: BrowserPage
        if let live = livePages[tab.id] {
            page = live.page
            livePages[tab.id]?.lastActive = .now
        } else {
            page = makePage(for: tab, profileID: profileID)
            livePages[tab.id] = LivePage(page: page, lastActive: .now)
        }
        page.returnVideoFromPictureInPicture()
        refreshHibernationSchedule()
        return page
    }

    public func deactivate() {
        leave(activeTabID, for: nil)
        markPreviousActiveAsIdle()
        activeTabID = nil
        refreshHibernationSchedule()
    }

    public func close(tabID: UUID) {
        if activeTabID == tabID { activeTabID = nil }
        hibernatedStates[tabID] = nil
        livePages.removeValue(forKey: tabID)?.page.dispose()
    }

    func hibernate(_ tabID: UUID) {
        guard tabID != activeTabID, let live = livePages.removeValue(forKey: tabID) else { return }
        hibernatedStates[tabID] = live.page.webView.interactionState
        live.page.dispose()
        Self.signposter.emitEvent(Diagnostics.Signpost.pageHibernated)
    }

    /// Pages take the setting from their next load; a site's own switch reloads it instead.
    public func refreshContentBlocking() {
        for live in livePages.values { live.page.updateContentBlocking() }
    }

    /// A video playing in the tab left behind moves to picture in picture when its site allows it,
    /// and comes back at once if the tab was selected again meanwhile.
    private func leave(_ tabID: UUID?, for nextTabID: UUID?) {
        guard let tabID, tabID != nextTabID, let page = livePages[tabID]?.page,
              let origin = page.webView.url.flatMap(SiteOrigin.init(url:)),
              delegate?.page(tabID, decisionFor: .automaticPictureInPicture, at: origin) == .allow else { return }
        Task { [weak self] in
            await page.moveVideoToPictureInPicture()
            if self?.activeTabID == tabID { page.returnVideoFromPictureInPicture() }
        }
    }

    private func makePage(for tab: BrowserTab, profileID: UUID) -> BrowserPage {
        let extensions = extensions(for: profileID)
        // An extension's own page needs its context's configuration.
        let configuration = NavigationInput.isExtensionURL(tab.url) ? extensions.configuration(for: tab.url) : nil
        let page = BrowserPage(configuration: configuration ?? BrowserPage.configuration(store: dataStore(for: profileID), extensions: extensions.controller))
        connect(page, to: tab.id)
        if let state = hibernatedStates.removeValue(forKey: tab.id) {
            page.restore(state, url: tab.url)
            Self.signposter.emitEvent(Diagnostics.Signpost.pageRestored)
        } else {
            page.load(tab.url)
            Self.signposter.emitEvent(Diagnostics.Signpost.pageCreated)
        }
        return page
    }

    private func connect(_ page: BrowserPage, to tabID: UUID) {
        page.onMetadata = { [weak self] url, title in self?.delegate?.page(tabID, didUpdateURL: url, title: title) }
        page.onVisit = { [weak self] url in self?.delegate?.page(tabID, didVisit: url) }
        page.onDownload = { [weak self] download in self?.downloads.track(download, from: tabID) }
        page.onIcons = { [weak self] links, url in self?.delegate?.page(tabID, didDeclareIcons: links, at: url) }
        page.onPopup = { [weak self] configuration, url in self?.openPopup(from: tabID, configuration: configuration, url: url) }
        page.onPermission = { [weak self] permission, origin in self?.delegate?.page(tabID, decisionFor: permission, at: origin) }
        page.onWebStoreButton = { [weak self, weak page] pressed in
            guard let url = page?.webView.url, let delegate = self?.delegate else { return nil }
            if pressed { await delegate.page(tabID, didPressWebStoreButtonAt: url) }
            return delegate.page(tabID, webStoreButtonAt: url)
        }
        page.contentBlocker = contentBlocker
        page.onClose = { [weak self] in
            guard let opener = self?.livePages[tabID]?.openerTabID else { return }
            self?.delegate?.pageDidRequestClose(tabID, openerTabID: opener)
        }
    }

    /// The popup must use WebKit's configuration unchanged: it carries the opener's data store,
    /// process and user scripts, and keeps `window.opener` connected. WebKit then loads the
    /// popup's request into the returned view itself.
    private func openPopup(from openerTabID: UUID, configuration: WKWebViewConfiguration, url: URL?) -> WKWebView? {
        guard livePages[openerTabID] != nil, let tab = delegate?.page(openerTabID, requestsPopupTabFor: url) else { return nil }
        let popup = BrowserPage(configuration: configuration)
        connect(popup, to: tab.id)
        livePages[tab.id] = LivePage(page: popup, lastActive: .now, openerTabID: openerTabID)
        Self.signposter.emitEvent(Diagnostics.Signpost.pageCreated)
        delegate?.pageDidOpenPopup(tab.id)
        return popup.webView
    }

    /// Unloading either side of a popup relationship would break `window.opener`.
    func hasPopupRelationship(_ tabID: UUID) -> Bool {
        if let opener = livePages[tabID]?.openerTabID, livePages[opener] != nil { return true }
        return livePages.values.contains { $0.openerTabID == tabID }
    }

    private func markPreviousActiveAsIdle() {
        guard let activeTabID else { return }
        livePages[activeTabID]?.lastActive = .now
    }
}
