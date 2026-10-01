import AppKit
import WebKit

/// App-provided extension integration, configured before the page registry creates a view.
@MainActor
public protocol PageExtensions: AnyObject {
    /// Adds the profile's extensions to the configuration of a page about to be created.
    func configure(_ configuration: WKWebViewConfiguration, forProfile profileID: UUID)
    /// The configuration an extension's own page, such as its options, needs to load in a tab; `nil` when none of the
    /// profile's extensions owns `url`.
    func configuration(forExtensionPage url: URL, inProfile profileID: UUID) -> WKWebViewConfiguration?
    /// A website can enter only an extension resource exposed to its native origin.
    func allowsWebsiteReturn(to target: URL, from origin: URL, inProfile profileID: UUID) -> Bool
    /// The extensions' items for the context menu the tab's page is opening.
    func menuItems(forTab tabID: UUID, inProfile profileID: UUID) -> [NSMenuItem]
}
