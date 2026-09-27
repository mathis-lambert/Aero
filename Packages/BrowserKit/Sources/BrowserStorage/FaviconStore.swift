import Foundation

/// Small downsampled site icons, one file per host inside each profile's folder.
/// Icons are a cache: a missing or unreadable file only means the site shows its fallback.
public actor FaviconStore {
    package enum Failure: Error { case iconTooLarge }
    package static let maximumIconBytes = 64 * 1024
    private static let fileExtension = "png"
    private static let fileNameCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-."))

    private let directory: URL
    private var writesUntilMaintenance = 0
    private static let maximumCacheBytes = 32 * 1024 * 1024
    private static let maximumFiles = 512
    private static let maximumAge: TimeInterval = 30 * 24 * 60 * 60

    public init(directory: URL) {
        self.directory = directory
    }

    public func icon(host: String, profileID: UUID) -> Data? {
        // Cache maintenance is best effort; a failed eviction never blocks browsing.
        if writesUntilMaintenance == 0 { try? prune() }
        guard let file = file(host: host, profileID: profileID),
              let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= Self.maximumIconBytes else { return nil }
        return try? Data(contentsOf: file)
    }

    public func save(_ data: Data, host: String, profileID: UUID) throws {
        guard data.count <= Self.maximumIconBytes else { throw Failure.iconTooLarge }
        guard let file = file(host: host, profileID: profileID) else { return }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        writesUntilMaintenance -= 1
        if writesUntilMaintenance <= 0 { try prune() }
    }

    public func removeProfile(_ profileID: UUID) throws {
        let folder = directory.appendingPathComponent(profileID.uuidString, isDirectory: true)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }

    /// At most 64 new writes between scans: 4 MiB / 64 files of bounded headroom.
    private func prune() throws {
        // A missing directory or failed scan must not repeat I/O on every cache lookup.
        writesUntilMaintenance = 64
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]) else { return }
        var entries: [(url: URL, size: Int, date: Date)] = []
        for case let file as URL in files where file.pathExtension == Self.fileExtension {
            let values = try file.resourceValues(forKeys: keys)
            guard values.isRegularFile == true else { continue }
            entries.append((file, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast))
        }
        entries.sort { $0.date > $1.date }
        let cutoff = Date.now.addingTimeInterval(-Self.maximumAge)
        var bytes = 0
        for (index, entry) in entries.enumerated() {
            bytes += entry.size
            if index >= Self.maximumFiles || bytes > Self.maximumCacheBytes || entry.date < cutoff {
                try FileManager.default.removeItem(at: entry.url)
            }
        }
    }

    /// Percent-encodes everything but letters, digits, hyphens and dots, so a host can never
    /// name a path outside the profile folder and distinct hosts never share a file.
    private func file(host: String, profileID: UUID) -> URL? {
        guard !host.isEmpty, let name = host.lowercased().addingPercentEncoding(withAllowedCharacters: Self.fileNameCharacters) else { return nil }
        return directory
            .appendingPathComponent(profileID.uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: false)
            .appendingPathExtension(Self.fileExtension)
    }
}
