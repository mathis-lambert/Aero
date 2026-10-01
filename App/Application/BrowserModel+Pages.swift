import BrowserCore
import BrowserWebKit
import Foundation

/// Live page events, applied to the session only while their tab still exists.
extension BrowserModel: WebPageRegistryDelegate {
    func isFavorite(_ tabID: UUID) -> Bool {
        session.tabs.first { $0.id == tabID }?.isFavorite == true
    }

    func page(_ tabID: UUID, didUpdateURL url: URL, title: String) {
        passwords.pageNavigated(tabID: tabID)
        updateTab(tabID, url: url, title: title)
    }

    func pageDidChangeLoading(_ tabID: UUID) {
        if let tab = session.tabs.first(where: { $0.id == tabID }) { extensionsDidChange(tab, .loading) }
    }

    func pageDidReplace(_ tabID: UUID) {
        passwords.pageNavigated(tabID: tabID)
        if window.selectedTabID == tabID { currentPage = pages.livePage(tabID) }
    }

    func page(_ tabID: UUID, didVisit visit: HistoryNavigation) {
        guard let tab = session.tabs.first(where: { $0.id == tabID }), let profileID = profileID(of: tab) else { return }
        history.recordVisit(to: visit.url, profileID: profileID, transition: visit.transition, referrer: visit.referrer)
        if visit.isWithinDocument { extensionsDidNavigateWithinDocument(tab, visit) }
    }

    func page(_ tabID: UUID, didDeclareIcons links: [FaviconLink], at url: URL) {
        guard let tab = session.tabs.first(where: { $0.id == tabID }),
              let key = faviconKey(for: tab, at: url) else { return }
        favicons.refresh(key, declaredIcons: links, at: url)
    }

    /// Popups stay in the opener's space, even after the user switched profiles. A popup without
    /// a web address yet (`about:blank`) starts with the opener's address until it navigates.
    func page(_ openerTabID: UUID, requestsPopupTabFor url: URL?) -> BrowserTab? {
        guard !isChangingStructure, let opener = session.tabs.first(where: { $0.id == openerTabID }) else { return nil }
        let address = url.flatMap { NavigationInput.isWebURL($0) ? $0 : nil } ?? opener.url
        return addTab(address, in: opener.spaceID)
    }

    func page(_ openerTabID: UUID, opensWindowWith page: BrowserPage, contentSize: CGSize) -> Bool {
        guard !isChangingStructure, let opener = session.tabs.first(where: { $0.id == openerTabID }), let profileID = profileID(of: opener) else { return false }
        popupWindows.append(PopupWindow(page: page, profileID: profileID, contentSize: contentSize, over: WindowConfiguration.mainWindow,
                                        discard: { [weak self] in self?.pages.discardDetachedPage($0) }) { [weak self] ended in
            self?.popupWindows.removeAll { $0 === ended }
        })
        return true
    }

    func pageDidOpenPopup(_ tabID: UUID, from openerTabID: UUID) {
        activateTab(tabID)
        extensionsDidOpenNavigationTarget(tabID, from: openerTabID)
    }

    func page(_ tabID: UUID, decisionFor permission: SitePermission, at origin: SiteOrigin) -> SiteDecision? {
        guard let tab = session.tabs.first(where: { $0.id == tabID }), let profileID = profileID(of: tab) else { return nil }
        return decision(for: permission, at: origin, profileID: profileID)
    }

    func pageDidRequestClose(_ tabID: UUID, openerTabID: UUID) {
        guard !isChangingStructure else { return }
        let wasSelected = window.selectedTabID == tabID
        closeTab(tabID, rememberForReopen: false)
        if wasSelected, tabs.contains(where: { $0.id == openerTabID }) { selectTab(openerTabID) }
    }
}
