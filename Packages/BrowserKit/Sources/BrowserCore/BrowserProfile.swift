import Foundation

/// Browsing identity shared by any number of spaces.
public struct BrowserProfile: Identifiable, Equatable, Sendable {
    public static let maximumNameLength = 40
    public let id: UUID
    public var name: String
    public package(set) var isRemoving = false
    public package(set) var sitePermissions: [SiteOrigin: [SitePermission: SiteDecision]] = [:]
    public package(set) var extensions: [InstalledExtension] = []

    public init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }

    public func decision(for permission: SitePermission, at origin: SiteOrigin) -> SiteDecision? {
        sitePermissions[origin]?[permission]
    }
}
