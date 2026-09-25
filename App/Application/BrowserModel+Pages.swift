import BrowserCore
import BrowserWebKit
import Foundation

/// Live page events, applied to the session only while their tab still exists.
extension BrowserModel: WebPageRegistryDelegate {
    func isPinned(_ tabID: UUID) -> Bool {
        session.tabs.first { $0.id == tabID }?.isPinned == true
    }

    func page(_ tabID: UUID, didUpdateURL url: URL, title: String) {
        updateTab(tabID, url: url, title: title)
    }

    func page(_ tabID: UUID, didVisit url: URL) {
        guard let tab = session.tabs.first(where: { $0.id == tabID }), let profileID = profileID(of: tab) else { return }
        history.recordVisit(to: url, profileID: profileID)
    }

    func page(_ tabID: UUID, didDeclareIcons links: [FaviconLink], at url: URL) {
        guard let tab = session.tabs.first(where: { $0.id == tabID }),
              let key = faviconKey(for: tab, at: url) else { return }
        favicons.refresh(key, declaredIcons: links, at: url)
    }

    /// Popups stay in the opener's space, even after the user switched profiles. A popup without
    /// a web address yet (`about:blank`) starts with the opener's address until it navigates.
    func page(_ openerTabID: UUID, requestsPopupTabFor url: URL?) -> BrowserTab? {
        guard let opener = session.tabs.first(where: { $0.id == openerTabID }) else { return nil }
        let address = url.flatMap { NavigationInput.isWebURL($0) ? $0 : nil } ?? opener.url
        return addTab(address, in: opener.spaceID)
    }

    func pageDidOpenPopup(_ tabID: UUID) {
        guard let tab = session.tabs.first(where: { $0.id == tabID }), tab.spaceID == space?.id else { return }
        selectTab(tabID)
    }

    func pageDidRequestClose(_ tabID: UUID, openerTabID: UUID) {
        let wasSelected = window.selectedTabID == tabID
        closeTab(tabID, rememberForReopen: false)
        if wasSelected, tabs.contains(where: { $0.id == openerTabID }) { selectTab(openerTabID) }
    }
}
