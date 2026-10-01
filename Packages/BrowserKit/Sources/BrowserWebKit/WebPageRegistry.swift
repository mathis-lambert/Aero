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
        let profileID: UUID
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
    /// Set before the first page is created.
    public weak var extensions: PageExtensions?
    public let downloads: DownloadCoordinator
    /// Developer mode: Web Inspector opens from every page's context menu (docs/BROWSING.md › Developer mode).
    public var pagesAreInspectable = false {
        didSet { for live in livePages.values { live.page.webView.isInspectable = pagesAreInspectable } }
    }
    private let contentBlocker: ContentBlocker?

    var livePages: [UUID: LivePage] = [:]
    var activeTabID: UUID?
    var policy: HibernationPolicy
    var evaluation: Task<Void, Never>?
    private static let maximumStateBytes = 16 * 1024 * 1024
    private static let maximumStates = 32
    /// A hibernated page's history and scroll position, and its `sessionStorage`, which a tab keeps while it lives.
    private struct HibernatedState {
        let interaction: Data
        let sessionStorage: Data?
        var bytes: Int { interaction.count + (sessionStorage?.count ?? 0) }
    }
    private var hibernatedStates: [UUID: HibernatedState] = [:]
    private var stateOrder: [UUID] = []
    private(set) var stores: [UUID: WKWebsiteDataStore] = [:]
    private var pressureMonitor: MemoryPressureMonitor?
    let ephemeral: Bool

    public convenience init(downloads: DownloadCoordinator, contentBlocker: ContentBlocker? = nil, ephemeral: Bool, hibernation: HibernationSettings = .default) {
        let limit = HibernationPolicy.liveBackgroundPageLimit(forPhysicalMemory: ProcessInfo.processInfo.physicalMemory)
        self.init(downloads: downloads, contentBlocker: contentBlocker, ephemeral: ephemeral, hibernation: hibernation, liveBackgroundPageLimit: limit)
    }

    package init(downloads: DownloadCoordinator, contentBlocker: ContentBlocker? = nil, ephemeral: Bool, hibernation: HibernationSettings,
                 liveBackgroundPageLimit: Int) {
        self.downloads = downloads
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

    /// The tab's page while it is loaded; hibernated and closed tabs have none.
    public func livePage(_ tabID: UUID) -> BrowserPage? { livePages[tabID]?.page }


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
            livePages[tab.id] = LivePage(page: page, profileID: profileID, lastActive: .now)
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
        discardState(tabID)
        livePages.removeValue(forKey: tabID)?.page.dispose()
    }

    func hibernate(_ tabID: UUID, sessionStorage: Data? = nil) {
        guard tabID != activeTabID, let live = livePages.removeValue(forKey: tabID) else { return }
        discardState(tabID)
        if let interaction = live.page.webView.interactionState as? Data {
            let state = HibernatedState(interaction: interaction, sessionStorage: sessionStorage)
            if state.bytes <= Self.maximumStateBytes {
                hibernatedStates[tabID] = state
                stateOrder.append(tabID)
                var bytes = hibernatedStates.values.reduce(0) { $0 + $1.bytes }
                while stateOrder.count > Self.maximumStates || bytes > Self.maximumStateBytes {
                    let oldest = stateOrder.removeFirst()
                    bytes -= hibernatedStates.removeValue(forKey: oldest)?.bytes ?? 0
                }
            }
        }
        live.page.dispose()
        Self.signposter.emitEvent(Diagnostics.Signpost.pageHibernated)
    }

    private func discardState(_ id: UUID) {
        hibernatedStates[id] = nil
        stateOrder.removeAll { $0 == id }
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
        // An extension's own page needs its context's configuration.
        let extensionPage = NavigationInput.isExtensionURL(tab.url) ? extensions?.configuration(forExtensionPage: tab.url, inProfile: profileID) : nil
        let page = BrowserPage(configuration: extensionPage ?? websiteConfiguration(forProfile: profileID))
        page.extensionOrigin = extensionPage == nil ? nil : tab.url
        connect(page, to: tab.id, profileID: profileID)
        // A file's read access is granted only by loading it again.
        if let state = hibernatedStates[tab.id], !tab.url.isFileURL {
            discardState(tab.id)
            page.restore(state.interaction, sessionStorage: state.sessionStorage, url: tab.url)
            Self.signposter.emitEvent(Diagnostics.Signpost.pageRestored)
        } else {
            discardState(tab.id)
            page.load(tab.url, transition: .autoTopLevel)
            Self.signposter.emitEvent(Diagnostics.Signpost.pageCreated)
        }
        return page
    }

    /// A website page's configuration: the profile's data store, Aero's page scripts and the profile's extensions.
    public func websiteConfiguration(forProfile profileID: UUID) -> WKWebViewConfiguration {
        let configuration = BrowserPage.configuration(store: dataStore(for: profileID))
        extensions?.configure(configuration, forProfile: profileID)
        return configuration
    }

    private func connect(_ page: BrowserPage, to tabID: UUID, profileID: UUID) {
        page.webView.isInspectable = pagesAreInspectable
        page.onMetadata = { [weak self] url, title in self?.delegate?.page(tabID, didUpdateURL: url, title: title) }
        page.onLoadingChange = { [weak self] in self?.delegate?.pageDidChangeLoading(tabID) }
        page.onVisit = { [weak self] visit in self?.delegate?.page(tabID, didVisit: visit) }
        page.onDownload = { [weak self] download in self?.downloads.track(download, from: tabID) }
        page.onIcons = { [weak self] links, url in self?.delegate?.page(tabID, didDeclareIcons: links, at: url) }
        page.onPopup = { [weak self] configuration, url, features in self?.openPopup(from: tabID, configuration: configuration, url: url, features: features) }
        page.onApplicationLink = { [weak self] url in self?.delegate?.page(tabID, requestsApplicationFor: url) }
        page.onPermission = { [weak self] permission, origin in self?.delegate?.page(tabID, decisionFor: permission, at: origin) }
        page.onDialog = { [weak self] dialog in await self?.delegate?.page(tabID, presents: dialog) ?? .dismissed }
        page.onContextMenu = { [weak self] in self?.extensions?.menuItems(forTab: tabID, inProfile: profileID) ?? [] }
        page.onPageNavigation = { [weak self, weak page] target, origin in
            guard let self, let page else { return false }
            return self.transition(page, tabID: tabID, profileID: profileID, to: target, from: origin)
        }
        page.onPasswordForm = { [weak self] event, frame in self?.delegate?.page(tabID, passwordForm: event, in: frame) }
        page.contentBlocker = contentBlocker
        page.onClose = { [weak self] in
            guard let opener = self?.livePages[tabID]?.openerTabID else { return }
            self?.delegate?.pageDidRequestClose(tabID, openerTabID: opener)
        }
    }

    /// The popup must use WebKit's configuration unchanged: it carries the opener's data store,
    /// process and user scripts, and keeps `window.opener` connected. WebKit then loads the
    /// popup's request into the returned view itself.
    private func openPopup(from openerTabID: UUID, configuration: WKWebViewConfiguration, url: URL?, features: WKWindowFeatures) -> WKWebView? {
        if Self.opensWindow(features) { return openPopupWindow(from: openerTabID, configuration: configuration, features: features) }
        guard let opener = livePages[openerTabID], let tab = delegate?.page(openerTabID, requestsPopupTabFor: url) else { return nil }
        let popup = BrowserPage(configuration: configuration)
        popup.extensionOrigin = opener.page.extensionOrigin
        connect(popup, to: tab.id, profileID: opener.profileID)
        livePages[tab.id] = LivePage(page: popup, profileID: opener.profileID, lastActive: .now, openerTabID: openerTabID)
        Self.signposter.emitEvent(Diagnostics.Signpost.pageCreated)
        delegate?.pageDidOpenPopup(tab.id, from: openerTabID)
        return popup.webView
    }

    /// Switches between the website and extension configurations at the page lifecycle owner.
    /// Replacing inside a navigation delegate call is deferred and guarded against newer navigation or closure.
    private func transition(_ page: BrowserPage, tabID: UUID, profileID: UUID, to request: URLRequest, from origin: URL?) -> Bool {
        guard let target = request.url else { return false }
        let targetIsExtension = NavigationInput.isExtensionURL(target)
        let sameExtension = page.extensionOrigin.map { $0.scheme == target.scheme && $0.host() == target.host() } == true
        if sameExtension || (!targetIsExtension && page.extensionOrigin == nil) { return false }
        let configuration: WKWebViewConfiguration
        if targetIsExtension {
            guard let origin, extensions?.allowsWebsiteReturn(to: target, from: origin, inProfile: profileID) == true,
                  let extensionPage = extensions?.configuration(forExtensionPage: target, inProfile: profileID) else { return false }
            configuration = extensionPage
        } else {
            guard NavigationInput.isWebURL(target) else { return false }
            configuration = websiteConfiguration(forProfile: profileID)
        }
        let revision = page.navigationRevision
        let generation = page.documentGeneration
        let transition = page.historyTransition, referrer = page.historyReferrer
        Task { @MainActor [weak self, weak page] in
            await Task.yield()
            guard let self, let page, self.livePages[tabID]?.page === page,
                  page.navigationRevision == revision, page.documentGeneration == generation else { return }
            self.replacePage(tabID, with: configuration, request: request, transition: transition, referrer: referrer)
        }
        return true
    }

    /// Programmatic navigation uses the same configuration boundary without a website resource grant.
    public func load(_ url: URL, inTab tabID: UUID) {
        guard let live = livePages[tabID] else { return }
        let targetIsExtension = NavigationInput.isExtensionURL(url)
        let sameExtension = live.page.extensionOrigin.map { $0.scheme == url.scheme && $0.host() == url.host() } == true
        if sameExtension || (!targetIsExtension && live.page.extensionOrigin == nil) { live.page.load(url); return }
        let configuration: WKWebViewConfiguration
        if targetIsExtension {
            guard let contextConfiguration = extensions?.configuration(forExtensionPage: url, inProfile: live.profileID) else { return }
            configuration = contextConfiguration
        } else {
            guard NavigationInput.isWebURL(url) else { return }
            configuration = websiteConfiguration(forProfile: live.profileID)
        }
        replacePage(tabID, with: configuration, request: URLRequest(url: url))
    }

    private func replacePage(_ tabID: UUID, with configuration: WKWebViewConfiguration, request: URLRequest,
                             transition: HistoryTransition = .typed, referrer: URL? = nil) {
        guard let live = livePages[tabID], let url = request.url else { return }
        let replacement = BrowserPage(configuration: configuration)
        replacement.extensionOrigin = NavigationInput.isExtensionURL(url) ? url : nil
        connect(replacement, to: tabID, profileID: live.profileID)
        live.page.dispose()
        livePages[tabID] = LivePage(page: replacement, profileID: live.profileID, lastActive: .now, openerTabID: live.openerTabID)
        delegate?.page(tabID, didUpdateURL: url, title: "")
        delegate?.pageDidReplace(tabID)
        replacement.load(request, transition: transition, referrer: referrer)
    }

    /// `window.open` with a size asks for a window of its own, as Safari opens one; without, the page opens in a tab.
    static func opensWindow(_ features: WKWindowFeatures) -> Bool { features.width != nil || features.height != nil }

    /// A popup window: a page outside any tab, with the opener's data and `window.opener`, recording no history.
    /// Its downloads, links for other apps, site permissions and further popups belong to its opener's tab.
    private func openPopupWindow(from openerTabID: UUID, configuration: WKWebViewConfiguration, features: WKWindowFeatures) -> WKWebView? {
        guard let opener = livePages[openerTabID] else { return nil }
        let popup = BrowserPage(configuration: configuration)
        popup.webView.isInspectable = pagesAreInspectable
        popup.extensionOrigin = opener.page.extensionOrigin
        popup.contentBlocker = contentBlocker
        popup.onDownload = { [weak self] download in self?.downloads.track(download, from: nil) }
        popup.onApplicationLink = { [weak self] url in self?.delegate?.page(openerTabID, requestsApplicationFor: url) }
        popup.onPermission = { [weak self] permission, origin in self?.delegate?.page(openerTabID, decisionFor: permission, at: origin) }
        popup.onPopup = { [weak self] configuration, url, features in self?.openPopup(from: openerTabID, configuration: configuration, url: url, features: features) }
        let size = CGSize(width: features.width?.doubleValue ?? 0, height: features.height?.doubleValue ?? 0)
        guard delegate?.page(openerTabID, opensWindowWith: popup, contentSize: size) == true else { return nil }
        Self.signposter.emitEvent(Diagnostics.Signpost.pageCreated)
        return popup.webView
    }

    /// A page outside any tab, for another app's sign-in (docs/OTHER_APPS.md › Sign-in for other apps). It uses the
    /// profile's website data and extensions, or, for a private sign-in, a store of its own that ends with the page.
    /// It records no history and opens no popups.
    public func makeSignInPage(profileID: UUID, isPrivate: Bool) -> BrowserPage {
        let configuration = isPrivate ? BrowserPage.configuration(store: .nonPersistent()) : websiteConfiguration(forProfile: profileID)
        let page = BrowserPage(configuration: configuration)
        page.webView.isInspectable = pagesAreInspectable
        page.contentBlocker = contentBlocker
        Self.signposter.emitEvent(Diagnostics.Signpost.pageCreated)
        return page
    }

    /// Ends a page outside any tab, a sign-in's or a popup window's: its web content process and, for a private
    /// sign-in, its website data go with it.
    public func discardDetachedPage(_ page: BrowserPage) { page.dispose() }

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

extension WebPageRegistry {
    /// Called only after all spaces have left the profile, its extensions are removed and the deletion intent has
    /// committed.
    public func removeProfile(_ profileID: UUID) async throws {
        stores[profileID] = nil
        if !ephemeral { try await WKWebsiteDataStore.remove(forIdentifier: profileID) }
    }
}
