import BrowserCore
import Foundation

/// The session owner behind live pages. Every call names the tab the event belongs to; the
/// delegate ignores tabs it no longer has, so late events cannot resurrect closed tabs.
@MainActor
public protocol WebPageRegistryDelegate: AnyObject {
    func isFavorite(_ tabID: UUID) -> Bool
    func page(_ tabID: UUID, didUpdateURL url: URL, title: String)
    /// The page started or finished loading.
    func pageDidChangeLoading(_ tabID: UUID)
    /// The page crossed the website/extension configuration boundary.
    func pageDidReplace(_ tabID: UUID)
    /// A native main-frame commit or a change of address within the document. Hibernation restores are excluded.
    func page(_ tabID: UUID, didVisit visit: HistoryNavigation)
    func page(_ tabID: UUID, didDeclareIcons links: [FaviconLink], at url: URL)
    /// Creates the record for a popup in the opener's space, or returns `nil` to block it.
    func page(_ openerTabID: UUID, requestsPopupTabFor url: URL?) -> BrowserTab?
    /// The page, or a link followed in one of its frames, asks to open `url` in another app; nothing was opened.
    func page(_ tabID: UUID, requestsApplicationFor url: URL)
    /// The popup's page is live; the tab may now be selected.
    func pageDidOpenPopup(_ tabID: UUID, from openerTabID: UUID)
    /// A popup called `window.close()`; its opener may be selected again.
    func pageDidRequestClose(_ tabID: UUID, openerTabID: UUID)
    /// The tab's profile's answer, with the browser-wide setting in place of a missing one, or `nil`
    /// for a device WebKit should ask for.
    func page(_ tabID: UUID, decisionFor permission: SitePermission, at origin: SiteOrigin) -> SiteDecision?
    /// A sign-in or sign-up form of the page, or of one of its frames, reported focus or a submission.
    func page(_ tabID: UUID, passwordForm event: PasswordFormEvent, in frame: PasswordFrame)
}
