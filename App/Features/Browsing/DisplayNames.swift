import BrowserCore
import Foundation

/// How the chrome names pages: by their title, or by their site when they have none.
extension URL {
    /// The host as people say it, without `www.` (`www.youtube.com` reads `youtube.com`), or the
    /// whole address when it has none.
    var siteName: String {
        guard let host = host(percentEncoded: false), !host.isEmpty else { return absoluteString }
        return host.hasPrefix("www.") && host.count > 4 ? String(host.dropFirst(4)) : host
    }
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
