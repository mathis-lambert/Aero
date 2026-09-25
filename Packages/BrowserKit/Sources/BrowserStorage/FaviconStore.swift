import Foundation

/// Small downsampled site icons, one file per host inside each profile's folder.
/// Icons are a cache: a missing or unreadable file only means the site shows its fallback.
public actor FaviconStore {
    public enum Failure: Error { case iconTooLarge }
    package static let maximumIconBytes = 64 * 1024
    private static let fileExtension = "png"
    private static let fileNameCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-."))

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func icon(host: String, profileID: UUID) -> Data? {
        guard let file = file(host: host, profileID: profileID) else { return nil }
        return try? Data(contentsOf: file)
    }

    public func save(_ data: Data, host: String, profileID: UUID) throws {
        guard data.count <= Self.maximumIconBytes else { throw Failure.iconTooLarge }
        guard let file = file(host: host, profileID: profileID) else { return }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
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
