@testable import Aero
import BrowserStorage
import Foundation
import Testing

// Only the most recently shown icons stay in memory. Written as failure modes first:
// 1. Showing an icon again reloads it: the lookup returns a new entry.
// 2. An icon shown recently is dropped while one not shown for longer stays.
// 3. The cache grows past its capacity.

@MainActor
struct FaviconCacheTests {
    private let profileID = UUID()

    private func key(_ index: Int) -> FaviconKey {
        FaviconKey(profileID: profileID, url: URL(string: "https://site\(index).example")!)!
    }

    @Test func recentlyShownIconsStayAndTheOldestGoes() {
        let cache = FaviconCache(store: FaviconStore(directory: FileManager.default.temporaryDirectory.appending(path: "aero-favicons-\(UUID())")))
        let kept = cache.favicon(for: key(0))
        let dropped = cache.favicon(for: key(1))
        #expect(cache.favicon(for: key(0)) === kept)
        for index in 2...FaviconCache.capacity {
            _ = cache.favicon(for: key(index))
            // Shown on every render, it stays the most recent.
            _ = cache.favicon(for: key(0))
        }
        _ = cache.favicon(for: key(FaviconCache.capacity + 1))
        #expect(cache.favicon(for: key(0)) === kept)
        #expect(cache.favicon(for: key(1)) !== dropped, "The icon not shown for longest left memory")
    }
}
