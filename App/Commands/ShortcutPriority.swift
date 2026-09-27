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
    // The held-modifier MRU gesture needs both key-down and release, which menu equivalents cannot provide.
    var supportsWebsitePriority: Bool { self != .recentTab && self != .previousRecentTab }
}
