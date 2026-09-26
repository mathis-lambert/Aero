import BrowserCore
import Foundation

/// The session owner behind live pages. Every call names the tab the event belongs to; the
/// delegate ignores tabs it no longer has, so late events cannot resurrect closed tabs.
@MainActor
public protocol WebPageRegistryDelegate: AnyObject {
    func isPinned(_ tabID: UUID) -> Bool
    func page(_ tabID: UUID, didUpdateURL url: URL, title: String)
    /// The page committed a new address; reloads and hibernation restores are not reported.
    func page(_ tabID: UUID, didVisit url: URL)
    func page(_ tabID: UUID, didDeclareIcons links: [FaviconLink], at url: URL)
    /// Creates the record for a popup in the opener's space, or returns `nil` to block it.
    func page(_ openerTabID: UUID, requestsPopupTabFor url: URL?) -> BrowserTab?
    /// The popup's page is live; the tab may now be selected.
    func pageDidOpenPopup(_ tabID: UUID)
    /// A popup called `window.close()`; its opener may be selected again.
    func pageDidRequestClose(_ tabID: UUID, openerTabID: UUID)
    /// The tab's profile's answer, with the browser-wide setting in place of a missing one, or `nil`
    /// for a device WebKit should ask for.
    func page(_ tabID: UUID, decisionFor permission: SitePermission, at origin: SiteOrigin) -> SiteDecision?
    /// Aero's install button on a Chrome Web Store page, or `nil` to leave the store's own.
    func page(_ tabID: UUID, webStoreButtonAt url: URL) -> WebStoreButton?
    /// Returns once the installation it started was answered.
    func page(_ tabID: UUID, didPressWebStoreButtonAt url: URL) async
}
