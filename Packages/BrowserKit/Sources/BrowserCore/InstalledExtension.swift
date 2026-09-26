import Foundation

/// An extension a profile installed. Its name, icon and requests come from its package; only where it
/// came from and the person's choices are kept. See docs/EXTENSIONS.md.
public struct InstalledExtension: Identifiable, Codable, Equatable, Sendable {
    public enum Source: Codable, Equatable, Sendable {
        case webStore
        /// Loaded unpacked for development; Reload reads the folder again.
        case folder(URL)
    }

    /// The Chrome Web Store identifier, or one derived the same way from a folder's path.
    public let id: String
    public var version: String
    public var source: Source
    public var isEnabled = true
    public var isPinned = false
    public var grantedPermissions: [String]
    public var grantedSites: [String]
    /// A store update that asks for more than was granted waits for the person's approval.
    public var pendingVersion: String?

    public init(id: String, version: String, source: Source, grantedPermissions: [String], grantedSites: [String]) {
        self.id = id
        self.version = version
        self.source = source
        self.grantedPermissions = grantedPermissions
        self.grantedSites = grantedSites
    }
}
