import AppKit
import BrowserCore
import BrowserStorage
import Foundation
import Observation

struct FaviconKey: Hashable {
    let profileID: UUID
    let host: String

    init?(profileID: UUID, url: URL) {
        guard NavigationInput.isWebURL(url), let host = url.host?.lowercased() else { return nil }
        self.profileID = profileID
        self.host = host
    }
}

/// One site's icon. Views observe the entries they show, so a new icon redraws only its own rows.
@MainActor @Observable
final class Favicon {
    fileprivate(set) var image: NSImage?
}

/// Site icons shown by the browser chrome: loaded from disk on first display, refreshed at most
/// once per host and profile per launch when a page declares its icons. Only the most recently
/// shown icons stay in memory; others are read from disk again when shown.
@MainActor
final class FaviconCache {
    /// Covers the sidebar and a few screens of history.
    private static let capacity = 256

    private let store: FaviconStore
    private let fetcher = FaviconFetcher()
    private var entries: [FaviconKey: Favicon] = [:]
    /// Least recently shown first.
    private var recent: [FaviconKey] = []
    private var refreshed: Set<FaviconKey> = []

    init(store: FaviconStore) {
        self.store = store
    }

    /// Looking an icon up starts reading it from disk the first time.
    func favicon(for key: FaviconKey) -> Favicon {
        recent.removeAll { $0 == key }
        recent.append(key)
        if let favicon = entries[key] { return favicon }
        let favicon = Favicon()
        entries[key] = favicon
        if recent.count > Self.capacity { entries[recent.removeFirst()] = nil }
        Task { [store] in
            guard let data = await store.icon(host: key.host, profileID: key.profileID), favicon.image == nil else { return }
            favicon.image = NSImage(data: data)
        }
        return favicon
    }

    func refresh(_ key: FaviconKey, declaredIcons links: [FaviconLink], at url: URL) {
        guard refreshed.insert(key).inserted else { return }
        let candidates = FaviconCandidate.ranked(from: links, pageURL: url)
        Task {
            guard let data = await fetcher.icon(from: candidates), let image = NSImage(data: data) else { return }
            favicon(for: key).image = image
            // Best effort: an icon that cannot be written is still shown and fetched again next launch.
            try? await store.save(data, host: key.host, profileID: key.profileID)
        }
    }
}
