import Foundation
import WebKit

/// What a profile's website data store occupies on disk. See docs/STORAGE.md › Storage settings.
public struct WebsiteDataUsage: Equatable, Sendable {
    public var cache: Int64 = 0
    /// Cookies, local storage, databases and service workers.
    public var siteData: Int64 = 0

    public init(cache: Int64 = 0, siteData: Int64 = 0) {
        self.cache = cache
        self.siteData = siteData
    }
}

extension WebPageRegistry {
    /// Folders WebKit keeps its caches in, inside a store's folder.
    private static let cacheFolders: Set<String> = ["NetworkCache", "CacheStorage", "MediaCache"]
    private static let cacheTypes: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache, WKWebsiteDataTypeFetchCache]

    /// Where WebKit keeps the persistent stores of this app. Read only, to estimate sizes.
    private static var storesFolder: URL {
        URL.libraryDirectory.appendingPathComponent("WebKit", isDirectory: true)
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? "", isDirectory: true)
            .appendingPathComponent("WebsiteDataStore", isDirectory: true)
    }

    /// Each profile's usage, and what stores of deleted profiles still occupy. Ephemeral stores use no disk.
    public func websiteDataUsage(profileIDs: Set<UUID>) async -> (profiles: [UUID: WebsiteDataUsage], unused: Int64) {
        guard !ephemeral else { return ([:], 0) }
        let identifiers = await WKWebsiteDataStore.allDataStoreIdentifiers
        let folder = Self.storesFolder, cacheFolders = Self.cacheFolders
        return await Task.detached(priority: .utility) {
            var profiles: [UUID: WebsiteDataUsage] = [:], unused: Int64 = 0
            for id in identifiers {
                let store = folder.appendingPathComponent(id.uuidString.lowercased(), isDirectory: true)
                var usage = WebsiteDataUsage()
                for child in (try? FileManager.default.contentsOfDirectory(at: store, includingPropertiesForKeys: nil)) ?? [] {
                    let size = DiskUsage.size(of: child)
                    if cacheFolders.contains(child.lastPathComponent) { usage.cache += size } else { usage.siteData += size }
                }
                if profileIDs.contains(id) { profiles[id] = usage } else { unused += usage.cache + usage.siteData }
            }
            return (profiles, unused)
        }.value
    }

    /// Caches only: sign-ins and site data stay.
    public func removeWebsiteCache(profileIDs: [UUID]) async {
        for id in profileIDs { await dataStore(for: id).removeData(ofTypes: Self.cacheTypes, modifiedSince: .distantPast) }
    }

    /// Everything the profile's store holds; its sites sign out.
    public func removeWebsiteData(profileID: UUID) async {
        await dataStore(for: profileID).removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
    }

    /// Stores left by deleted profiles. `keeping` lists every profile, including those being deleted.
    public func removeUnusedWebsiteData(keeping profileIDs: Set<UUID>) async throws {
        guard !ephemeral else { return }
        for id in await WKWebsiteDataStore.allDataStoreIdentifiers where !profileIDs.contains(id) && stores[id] == nil {
            try await WKWebsiteDataStore.remove(forIdentifier: id)
        }
    }

    /// Reset only: every store of this app, before any page or store exists. Test runs own none. See docs/STORAGE.md › Reset.
    public func removeAllWebsiteData() async throws {
        guard !ephemeral else { return }
        for id in await WKWebsiteDataStore.allDataStoreIdentifiers { try await WKWebsiteDataStore.remove(forIdentifier: id) }
    }
}

/// Bytes a file or folder occupies on disk. Blocking: call it off the main actor.
public enum DiskUsage {
    public static func size(of url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        if let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true {
            return Int64(values.totalFileAllocatedSize ?? 0)
        }
        guard let files = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in files {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
