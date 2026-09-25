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
}
