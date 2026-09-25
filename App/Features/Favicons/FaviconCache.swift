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

/// Site icons shown by the browser chrome: loaded from disk on first display, refreshed at most
/// once per host and profile per launch when a page declares its icons.
@MainActor @Observable
final class FaviconCache {
    private(set) var images: [FaviconKey: NSImage] = [:]
    @ObservationIgnored private let store: FaviconStore
    @ObservationIgnored private let fetcher = FaviconFetcher()
    @ObservationIgnored private var loaded: Set<FaviconKey> = []
    @ObservationIgnored private var refreshed: Set<FaviconKey> = []

    init(store: FaviconStore) {
        self.store = store
    }

    func load(_ key: FaviconKey) async {
        guard loaded.insert(key).inserted, let data = await store.icon(host: key.host, profileID: key.profileID) else { return }
        if images[key] == nil { images[key] = NSImage(data: data) }
    }

    func refresh(_ key: FaviconKey, declaredIcons links: [FaviconLink], at url: URL) {
        guard refreshed.insert(key).inserted else { return }
        let candidates = FaviconCandidate.ranked(from: links, pageURL: url)
        Task {
            guard let data = await fetcher.icon(from: candidates), let image = NSImage(data: data) else { return }
            images[key] = image
            // Best effort: an icon that cannot be written is still shown and fetched again next launch.
            try? await store.save(data, host: key.host, profileID: key.profileID)
        }
    }
}
