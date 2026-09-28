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
    fileprivate(set) var color: NSColor?
    @ObservationIgnored fileprivate var attemptedFallback = false

    fileprivate func setImage(_ image: NSImage, color: FaviconColor?) {
        self.image = image
        self.color = color.map { NSColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: 1) }
    }
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
    private var refreshTasks: [FaviconKey: Task<Void, Never>] = [:]
    private var fallbackTasks: [FaviconKey: Task<Void, Never>] = [:]
    private var refreshed: Set<FaviconKey> = []

    init(store: FaviconStore) {
        self.store = store
    }

    isolated deinit {
        refreshTasks.values.forEach { $0.cancel() }
        fallbackTasks.values.forEach { $0.cancel() }
    }

    func removeProfile(_ id: UUID) async throws {
        let pending = refreshTasks.filter { $0.key.profileID == id }.map(\.value)
            + fallbackTasks.filter { $0.key.profileID == id }.map(\.value)
        pending.forEach { $0.cancel() }
        // Drain any cache write already submitted before removing the profile directory.
        for task in pending { await task.value }
        entries = entries.filter { $0.key.profileID != id }
        recent.removeAll { $0.profileID == id }
        refreshed = refreshed.filter { $0.profileID != id }
        try await store.removeProfile(id)
    }

    /// Icons another browser had for imported pages. An icon already on disk is kept; each is scaled like a fetched one.
    func adopt(_ icons: [URL: Data], profileID: UUID) async {
        let keyed = icons.compactMap { url, data in FaviconKey(profileID: profileID, url: url).map { ($0, data) } }
        let scaled = await Task.detached(priority: .utility) {
            keyed.compactMap { key, data in FaviconFetcher.downsampledPNG(from: data).map { (key, $0) } }
        }.value
        for (key, data) in scaled {
            guard await store.icon(host: key.host, profileID: key.profileID) == nil, let image = NSImage(data: data) else { continue }
            // Best effort, as for fetched icons: one that cannot be written is fetched again later.
            try? await store.save(data, host: key.host, profileID: key.profileID)
            if let favicon = entries[key], favicon.image == nil { favicon.setImage(image, color: await FaviconColor.extract(from: data)) }
        }
    }

    /// Clearing Settings › Storage: icons are fetched again as pages load.
    func removeAll() async throws {
        let pending = Array(refreshTasks.values) + Array(fallbackTasks.values)
        pending.forEach { $0.cancel() }
        for task in pending { await task.value }
        entries = [:]
        recent = []
        refreshed = []
        try await store.removeAll()
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
            let color = await FaviconColor.extract(from: data)
            guard favicon.image == nil, let image = NSImage(data: data) else { return }
            favicon.setImage(image, color: color)
        }
        return favicon
    }

    func refresh(_ key: FaviconKey, declaredIcons links: [FaviconLink], at url: URL) {
        guard refreshed.insert(key).inserted else { return }
        fallbackTasks[key]?.cancel()
        let candidates = FaviconCandidate.ranked(from: links, pageURL: url)
        refreshTasks[key] = Task { [weak self, fetcher, store] in
            defer { self?.refreshTasks[key] = nil }
            guard let data = await fetcher.icon(from: candidates), let image = NSImage(data: data), !Task.isCancelled else { return }
            let color = await FaviconColor.extract(from: data)
            guard !Task.isCancelled else { return }
            self?.favicon(for: key).setImage(image, color: color)
            // Best effort: an icon that cannot be written is still shown and fetched again next launch.
            try? await store.save(data, host: key.host, profileID: key.profileID)
        }
    }

    /// A visible saved login may have no open tab. Ask only that host for its conventional icon,
    /// once while its bounded cache entry lives, and never if an icon is already on disk.
    func fetchMissing(_ key: FaviconKey, at url: URL) {
        let favicon = favicon(for: key)
        guard favicon.image == nil, !favicon.attemptedFallback, refreshTasks[key] == nil else { return }
        favicon.attemptedFallback = true
        let candidates = FaviconCandidate.ranked(from: [], pageURL: url)
        guard !candidates.isEmpty else { return }
        fallbackTasks[key] = Task { [weak self, fetcher, store] in
            defer { self?.fallbackTasks[key] = nil }
            guard await store.icon(host: key.host, profileID: key.profileID) == nil,
                  !Task.isCancelled,
                  let data = await fetcher.icon(from: candidates),
                  let image = NSImage(data: data),
                  let self, !Task.isCancelled, !self.refreshed.contains(key) else { return }
            let color = await FaviconColor.extract(from: data)
            guard !Task.isCancelled, !self.refreshed.contains(key) else { return }
            self.favicon(for: key).setImage(image, color: color)
            try? await store.save(data, host: key.host, profileID: key.profileID)
        }
    }
}
