import AppKit
import BrowserCore
import BrowserWebKit
import Foundation

/// What Aero keeps on this Mac, in bytes. See docs/STORAGE.md › Storage settings.
struct StorageUsage: Equatable {
    var websiteCache: Int64 = 0
    /// Each profile's cookies and site data.
    var siteData: [UUID: Int64] = [:]
    /// Website data stores of deleted profiles.
    var unusedSiteData: Int64 = 0
    var history: Int64 = 0
    var icons: Int64 = 0
    var blockingLists: Int64 = 0
    var extensions: Int64 = 0
    var records: Int64 = 0

    func size(of item: StorageItem) -> Int64 {
        switch item {
        case .websiteCache: websiteCache
        case .siteData: siteData.values.reduce(unusedSiteData, +)
        case .history: history
        case .icons: icons
        case .blockingLists: blockingLists
        case .extensions: extensions
        case .records: records
        }
    }

    var total: Int64 { StorageItem.allCases.reduce(0) { $0 + size(of: $1) } }

    private static let historyFiles = ["History.sqlite", "History.sqlite-wal", "History.sqlite-shm"]
    private static let iconsFolder = "Favicons"
    private static let blockingFolders = ["Filter Lists", "Content Rules"]

    /// Aero's own folders. Blocking: call it off the main actor.
    nonisolated static func files(in location: StorageLocation) -> StorageUsage {
        var usage = StorageUsage()
        let files = { (folder: URL) in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] }
        for file in files(location.data) {
            let size = DiskUsage.size(of: file)
            switch file.lastPathComponent {
            case let name where historyFiles.contains(name): usage.history += size
            case "Extensions": usage.extensions += size
            // Test runs only: downloads are the person's files, not Aero's.
            case "Downloads": continue
            default: usage.records += size
            }
        }
        for file in files(location.caches) {
            let size = DiskUsage.size(of: file)
            switch file.lastPathComponent {
            case iconsFolder: usage.icons += size
            case let name where blockingFolders.contains(name): usage.blockingLists += size
            // What WebKit keeps in the app's caches folder.
            default: usage.websiteCache += size
            }
        }
        return usage
    }
}

/// The parts of the storage bar, in its order.
enum StorageItem: String, CaseIterable, Identifiable {
    case siteData, websiteCache, history, extensions, icons, blockingLists, records
    var id: Self { self }
}

extension BrowserModel {
    /// Measured off the main actor.
    func storageUsage() async -> StorageUsage {
        let web = await pages.websiteDataUsage(profileIDs: Set(session.profiles.map(\.id)))
        let location = storageLocation
        var usage = await Task.detached(priority: .utility) { StorageUsage.files(in: location) }.value
        for (id, profile) in web.profiles {
            usage.websiteCache += profile.cache
            usage.siteData[id] = profile.siteData
        }
        usage.unusedSiteData = web.unused
        return usage
    }

    /// Caches only; sign-ins stay.
    func clearWebsiteCache() async {
        await pages.removeWebsiteCache(profileIDs: profiles.map(\.id))
    }

    func clearSiteData(profileID: UUID) async {
        await pages.removeWebsiteData(profileID: profileID)
    }

    func removeUnusedSiteData() async throws {
        try await pages.removeUnusedWebsiteData(keeping: Set(session.profiles.map(\.id)))
    }

    func clearIcons() async throws {
        try await favicons.removeAll()
    }

    /// Every profile's history, then the file gives its space back.
    func clearAllHistory() async throws {
        for profile in session.profiles { try await history.clear(profileID: profile.id, since: nil) }
        try await history.compact()
    }

    // MARK: - Reset

    /// Deletes the passwords now, then quits; the next launch erases the rest before anything opens.
    /// See docs/STORAGE.md › Reset.
    func reset() async throws {
        for profile in session.profiles { try await passwords.store.removeAll(profileID: profile.id) }
        preferences.markResetPending()
        if !isTestRun {
            // Reopens Aero once this process has exited, so two instances never share the store.
            let relaunch = Process()
            relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
            relaunch.arguments = ["-c", "while /bin/kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do /bin/sleep 0.2; done; /usr/bin/open \"$0\"",
                                  Bundle.main.bundlePath]
            try relaunch.run()
        }
        // From the run loop, not this task: termination waits in a nested loop for the final save, which runs on the main queue.
        RunLoop.main.perform { MainActor.assumeIsolated { NSApp.terminate(nil) } }
    }

    /// At launch, before any store exists. `false` when files remain; the pending mark is then kept for the next launch.
    static func eraseForReset(_ location: StorageLocation) -> Bool {
        var erased = true
        for folder in [location.data, location.caches] where FileManager.default.fileExists(atPath: folder.path) {
            do { try FileManager.default.removeItem(at: folder) } catch { erased = false }
        }
        return erased
    }
}
