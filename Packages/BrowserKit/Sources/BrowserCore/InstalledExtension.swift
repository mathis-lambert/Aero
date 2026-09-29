import Foundation

/// An extension a profile installed. Its name, icon and requests come from its package; only where it
/// came from and the person's choices are kept. See docs/EXTENSIONS.md.
public struct InstalledExtension: Identifiable, Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case webStore
        /// Loaded unpacked for development; Reload reads the folder again.
        case folder(URL)
    }

    /// The Chrome Web Store identifier, or one derived the same way from a folder's path.
    public let id: String
    /// Immutable package directory. Changing a candidate never changes the active package.
    public var packageID: UUID
    /// Durable uninstall intent, completed on launch if interrupted.
    public var isRemoving = false
    public var version: String
    public var source: Source
    public var isEnabled = true
    public var isPinned = false
    public var grantedPermissions: [String]
    public var grantedSites: [String]
    /// A store update that asks for more than was granted waits for the person's approval.
    public var pendingVersion: String?

    var isValid: Bool {
        Self.isValidIdentifier(id)
            && Set(grantedPermissions).count == grantedPermissions.count
            && Set(grantedSites).count == grantedSites.count
    }

    /// Chrome's 32 ASCII letters a–p, shared by stored records and Web Store addresses.
    public static func isValidIdentifier(_ value: String) -> Bool {
        value.utf8.count == 32 && value.utf8.allSatisfy { $0 >= 97 && $0 <= 112 }
    }

    public init(id: String, version: String, source: Source, grantedPermissions: [String], grantedSites: [String]) {
        self.id = id
        self.packageID = UUID()
        self.version = version
        self.source = source
        self.grantedPermissions = grantedPermissions
        self.grantedSites = grantedSites
    }
}
