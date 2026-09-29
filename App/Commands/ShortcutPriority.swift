import BrowserCore
import Foundation

/// Only explicit priority choices are persisted; Automatic inherits the command's catalog policy.
enum ShortcutPriority: String, Codable, CaseIterable, Identifiable {
    case automatic, browser, website
    var id: Self { self }
    var title: String {
        switch self {
        case .automatic: String(localized: "Default priority")
        case .browser: String(localized: "Use Aero first")
        case .website: String(localized: "Use website first")
        }
    }
}

extension BrowserCommand {
    /// A page can pass a shortcut on only to a menu item. Moves use submenus; the held-modifier
    /// MRU gesture needs key-down and release. See docs/SHORTCUTS.md › Menus.
    var supportsWebsitePriority: Bool {
        switch self {
        case .tab1, .tab2, .tab3, .tab4, .tab5, .tab6, .tab7, .tab8, .lastTab, .recentTab, .previousRecentTab,
             .moveToGroup, .moveToSpace, .profiles, .newProfile, .passwords, .clearCookies, .clearCache: false
        default: true
        }
    }
}
