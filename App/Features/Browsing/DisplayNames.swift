import BrowserCore
import Foundation

/// How the chrome names pages: by their title, or by their site when they have none.
extension URL {
    /// The host, or the whole address when it has none.
    var siteName: String { host ?? absoluteString }
}

extension BrowserTab {
    var displayTitle: String {
        if let page = InternalPage(url: url) { return page.title }
        return title.isEmpty ? url.siteName : title
    }
}

extension HistoryEntry {
    var displayTitle: String { title.isEmpty ? url.siteName : title }
}
