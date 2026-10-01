import BrowserCore
import Foundation

/// How the chrome names pages: by the name given to their tab, their title, or their site.
extension URL {
    /// The host as people say it, without `www.` (`www.youtube.com` reads `youtube.com`), or the
    /// whole address when it has none.
    var siteName: String {
        guard let host = host(percentEncoded: false), !host.isEmpty else { return absoluteString }
        return host.hasPrefix("www.") && host.count > 4 ? String(host.dropFirst(4)) : host
    }
}

extension URL {
    /// An application bundle's name as macOS shows it in menus and the Dock.
    var applicationName: String {
        let bundle = Bundle(url: self)
        let name = bundle?.localizedInfoDictionary?["CFBundleDisplayName"] ?? bundle?.infoDictionary?["CFBundleDisplayName"]
            ?? bundle?.infoDictionary?["CFBundleName"]
        return name as? String ?? deletingPathExtension().lastPathComponent
    }
}

extension BrowserTab {
    var displayTitle: String {
        if let name { return name }
        if let page = InternalPage(url: url) { return page.title }
        return title.isEmpty ? url.siteName : title
    }
}

extension HistoryEntry {
    var displayTitle: String { title.isEmpty ? url.siteName : title }
}
