import AppKit
import BrowserCore
import BrowserExtensions
import BrowserWebKit
import Foundation
import WebKit

// MARK: - Pages

extension BrowserModel: PageExtensions {
    func configure(_ configuration: WKWebViewConfiguration, forProfile profileID: UUID) {
        extensions.configure(configuration, forProfile: profileID)
    }

    func configuration(forExtensionPage url: URL, inProfile profileID: UUID) -> WKWebViewConfiguration? {
        extensions.configuration(forExtensionPage: url, inProfile: profileID)
    }

    func allowsWebsiteReturn(to target: URL, from origin: URL, inProfile profileID: UUID) -> Bool {
        extensions.allowsWebsiteReturn(to: target, from: origin, inProfile: profileID)
    }

    func menuItems(forTab tabID: UUID, inProfile profileID: UUID) -> [NSMenuItem] {
        extensions.menuItems(forTab: tabID, inProfile: profileID)
    }
}

// MARK: - ExtensionHost

extension BrowserModel: ExtensionHost {
    func tabIDs(inProfile profileID: UUID) -> [UUID] {
        let spaces = Set(session.spaces.filter { $0.profileID == profileID }.map(\.id))
        return session.tabs.filter { spaces.contains($0.spaceID) }.map(\.id)
    }

    func selectedTabID(inProfile profileID: UUID) -> UUID? { profile?.id == profileID ? window.selectedTabID : nil }

    func tab(_ tabID: UUID) -> BrowserTab? { session.tabs.first { $0.id == tabID } }

    func webView(forTab tabID: UUID) -> WKWebView? { pages.livePage(tabID)?.webView }

    func openTab(_ url: URL, inProfile profileID: UUID, selected: Bool) -> UUID? {
        guard !isChangingStructure, let space = destinationSpace(for: profileID), let tab = addTab(url, in: space.id) else { return nil }
        if selected, profile?.id == profileID { selectTab(tab.id) }
        return tab.id
    }

    /// The page an extension of the profile shows in place of Aero's New Tab page, if one does.
    func extensionNewTabPage(inProfile profileID: UUID) -> URL? {
        extensions.extensionsIfMade(for: profileID)?.newTabPageURL(order: installedExtensions(inProfile: profileID).filter(\.isEnabled).map(\.id))
    }

    func showNewTab(inProfile profileID: UUID) {
        guard !isChangingStructure, let space = destinationSpace(for: profileID) else { return }
        switchSpace(space.id)
        perform(.newTab)
    }

    func activateTab(_ tabID: UUID) {
        guard let tab = tab(tabID), !isChangingStructure else { return }
        showTab(tab)
    }

    func removeTab(_ tabID: UUID) { closeTab(tabID, rememberForReopen: true) }

    func copyTab(_ tabID: UUID) -> UUID? { duplicateTab(tabID, select: false) }

    /// A loaded page follows the address; an unloaded tab takes it and loads it when shown.
    func load(_ url: URL, inTab tabID: UUID) {
        guard !isChangingStructure, tab(tabID) != nil, NavigationInput.isWebURL(url) || NavigationInput.isExtensionURL(url) else { return }
        if pages.livePage(tabID) != nil { pages.load(url, inTab: tabID); return }
        pages.close(tabID: tabID)
        session.updateTab(id: tabID, url: url, title: "")
        persist()
    }

    func reloadTab(_ tabID: UUID, fromOrigin: Bool) {
        guard let page = pages.livePage(tabID) else { return }
        if fromOrigin { page.reloadFromOrigin() } else { page.reload() }
    }

    func goBack(inTab tabID: UUID) { pages.livePage(tabID)?.goBack() }
    func goForward(inTab tabID: UUID) { pages.livePage(tabID)?.goForward() }

    func setPinned(_ pinned: Bool, tab tabID: UUID) {
        guard let tab = tab(tabID), tab.isFavorite != pinned else { return }
        moveTab(tabID, to: pinned ? .grid : .open, before: nil)
    }

    func setZoom(_ factor: Double, tab tabID: UUID) {
        guard let tab = tab(tabID), let page = pages.livePage(tabID) else { return }
        page.setZoom(factor)
        extensionsDidChange(tab, .zoomFactor)
    }

    var mainWindow: NSWindow? { WindowConfiguration.mainWindow }

    func websiteConfiguration(forProfile profileID: UUID) -> WKWebViewConfiguration { pages.websiteConfiguration(forProfile: profileID) }

    /// Anchored to the extension's button when it shows, otherwise to the control center's.
    func presentPopup(_ popover: NSPopover, for extensionID: String, inProfile profileID: UUID) {
        guard profile?.id == profileID else { return }
        window.controlCenterPresented = false
        guard let anchor = window.extensionAnchors.object(forKey: extensionID as NSString)
                ?? window.extensionAnchors.object(forKey: ExtensionAnchor.controlCenter as NSString) else { return }
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }

    func requestPermissions(_ permissions: Set<String>, sites: Set<String>, for extensionID: String, inProfile profileID: UUID) async -> Bool {
        guard var record = installedExtensions(inProfile: profileID).first(where: { $0.id == extensionID }) else { return false }
        guard beginExtensionOperation(extensionID, profileID: profileID) else { return false }
        defer { endExtensionOperation(extensionID, profileID: profileID) }
        let webExtension = extensions.extensionsIfMade(for: profileID)?.contexts[extensionID]?.webExtension
        guard await ask(.permissions, name: webExtension?.displayName ?? extensionID, icon: webExtension?.icon(for: Self.reviewIconSize),
                        permissions: permissions.sorted(), sites: sites.sorted()) else { return false }
        record.grantedPermissions = Array(Set(record.grantedPermissions).union(permissions)).sorted()
        record.grantedSites = Array(Set(record.grantedSites).union(sites)).sorted()
        return await commitExtension(record, id: record.id, inProfile: profileID)
    }

    func extensionDidRemovePermissions(_ permissions: Set<String>, sites: Set<String>, of extensionID: String, inProfile profileID: UUID) {
        guard var record = installedExtensions(inProfile: profileID).first(where: { $0.id == extensionID }) else { return }
        record.grantedPermissions.removeAll(where: permissions.contains)
        record.grantedSites.removeAll(where: sites.contains)
        Task { await commitExtension(record, id: extensionID, inProfile: profileID) }
    }

    /// `management.uninstall` and `uninstallSelf`: the person confirms, as Chrome asks.
    func extensionRequestsRemoval(_ extensionID: String, by requester: String, inProfile profileID: UUID) {
        guard let record = installedExtension(extensionID, inProfile: profileID) else { return }
        Task {
            let kind: ExtensionRequest.Kind = requester == extensionID ? .removal : .management(.removal, by: extensionName(requester, inProfile: profileID))
            guard await ask(kind, name: extensionName(extensionID, inProfile: profileID), icon: extensionIcon(extensionID, inProfile: profileID)) else { return }
            await removeExtension(record, inProfile: profileID)
        }
    }

    /// `management.setEnabled`: the person confirms turning another extension on or off.
    func extensionRequestsEnabling(_ extensionID: String, _ enabled: Bool, by requester: String, inProfile profileID: UUID) async -> Bool {
        guard let record = installedExtension(extensionID, inProfile: profileID) else { return false }
        if record.isEnabled == enabled { return true }
        guard await ask(.management(enabled ? .enabling : .disabling, by: extensionName(requester, inProfile: profileID)),
                        name: extensionName(extensionID, inProfile: profileID), icon: extensionIcon(extensionID, inProfile: profileID)) else { return false }
        await setEnabled(enabled, record, inProfile: profileID)
        return installedExtension(extensionID, inProfile: profileID)?.isEnabled == enabled
    }

    private func extensionName(_ extensionID: String, inProfile profileID: UUID) -> String {
        extensions.extensionsIfMade(for: profileID)?.contexts[extensionID]?.webExtension.displayName ?? extensionID
    }

    private func extensionIcon(_ extensionID: String, inProfile profileID: UUID) -> NSImage? {
        extensions.extensionsIfMade(for: profileID)?.contexts[extensionID]?.webExtension.icon(for: Self.reviewIconSize)
    }

    func installedExtension(_ extensionID: String, inProfile profileID: UUID) -> InstalledExtension? {
        installedExtensions(inProfile: profileID).first { $0.id == extensionID }
    }

    func webStoreButton(for extensionID: String, inProfile profileID: UUID) -> WebStoreButton {
        installedExtension(extensionID, inProfile: profileID) != nil
            ? WebStoreButton(title: String(localized: "Added to Aero"), isEnabled: false)
            : WebStoreButton(title: String(localized: "Add to Aero"), isEnabled: true)
    }

    func installFromWebStore(_ extensionID: String, inProfile profileID: UUID) async {
        await installFromWebStore(extensionID, inProfile: profileID, inSettings: false)
    }

    func showNotification(_ notification: ExtensionNotification) async throws {
        try await extensionNotifications.show(notification)
    }

    func removeNotification(_ identifier: String, of extensionID: String, inProfile profileID: UUID) {
        extensionNotifications.remove(identifier, of: extensionID, inProfile: profileID)
    }

    func notificationsAllowed() async -> Bool { await extensionNotifications.isAllowed() }

    func shownNotifications(of extensionID: String, inProfile profileID: UUID) async -> Set<String> {
        await extensionNotifications.shown(of: extensionID, inProfile: profileID)
    }

    func download(_ request: URLRequest, filename: String?, inProfile profileID: UUID) async -> ExtensionDownload? {
        let download = await downloads.start(request, in: pages.dataStore(for: profileID), filename: filename)
        return DownloadForExtension(download) { [weak self] in self?.downloads.cancel(download) }
    }

    func revealDownloads(_ file: URL?) {
        if let file { NSWorkspace.shared.activateFileViewerSelecting([file]) }
        else { NSWorkspace.shared.open(downloads.directory) }
    }

    func searchURL(for text: String, inProfile profileID: UUID) -> URL? {
        guard session.profiles.contains(where: { $0.id == profileID }) else { return nil }
        return webSearch.searchURL(for: text)
    }
}

/// A download an extension started, as the extension sees it.
@MainActor
private final class DownloadForExtension: ExtensionDownload {
    let download: BrowserDownload
    private let cancelDownload: () -> Void

    init(_ download: BrowserDownload, cancel: @escaping () -> Void) {
        self.download = download
        cancelDownload = cancel
    }

    var sourceURL: URL? { download.sourceURL }
    var finalURL: URL? { download.finalURL }
    var mimeType: String? { download.mimeType }
    var destination: URL? { download.destination }
    var endTime: Date? { download.endTime }
    var canResume: Bool { download.state == .failed && download.canResume }
    var receivedBytes: Int64 { download.completedBytes }
    var totalBytes: Int64? { download.totalBytes }
    var state: ExtensionDownloadState {
        switch download.state {
        case .downloading: .inProgress
        case .finished: .complete
        case .failed, .cancelled: .interrupted
        }
    }

    func cancel() { cancelDownload() }
}
