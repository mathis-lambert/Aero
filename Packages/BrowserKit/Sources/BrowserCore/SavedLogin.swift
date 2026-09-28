import Foundation

/// A login saved in a profile, without its password: the keychain hands that out on its own.
/// See docs/PASSWORDS.md › Model.
public struct SavedLogin: Identifiable, Hashable, Sendable {
    public let profileID: UUID
    public let origin: SiteOrigin
    public let username: String
    public let lastUsed: Date?

    public init(profileID: UUID, origin: SiteOrigin, username: String, lastUsed: Date? = nil) {
        self.profileID = profileID
        self.origin = origin
        self.username = username
        self.lastUsed = lastUsed
    }

    public var id: String { "\(profileID.uuidString)\u{1}\(origin.rawValue)\u{1}\(username)" }
}

/// A login with its password, as it goes into the keychain, comes out of an import or into an export.
public struct LoginRecord: Equatable, Sendable {
    public let origin: SiteOrigin
    public let username: String
    public let password: String

    public init(origin: SiteOrigin, username: String, password: String) {
        self.origin = origin
        self.username = username
        self.password = password
    }
}

/// Which saved logins a page may be offered. See docs/PASSWORDS.md › Matching sites.
public enum LoginMatching {
    /// The origin's own logins first, then those of the same registrable domain, by last use. An HTTPS
    /// login is never offered over HTTP; an HTTP one may be offered on the site over HTTPS. A host
    /// without a registrable domain (`localhost`, an address) matches only itself, on any port.
    public static func candidates(_ logins: [SavedLogin], for origin: SiteOrigin, suffixes: PublicSuffixList) -> [SavedLogin] {
        let site = suffixes.registrableDomain(of: origin.host)
        let offered = logins.filter { login in
            guard login.origin.scheme == origin.scheme || (login.origin.scheme == "http" && origin.scheme == "https") else { return false }
            if login.origin == origin { return true }
            if let site { return suffixes.registrableDomain(of: login.origin.host) == site }
            return login.origin.host == origin.host
        }
        return offered.sorted { first, second in
            let firstExact = first.origin == origin, secondExact = second.origin == origin
            if firstExact != secondExact { return firstExact }
            let firstUsed = first.lastUsed ?? .distantPast, secondUsed = second.lastUsed ?? .distantPast
            if firstUsed != secondUsed { return firstUsed > secondUsed }
            return first.username.localizedStandardCompare(second.username) == .orderedAscending
        }
    }
}

extension SiteOrigin {
    public var scheme: String { String(rawValue.prefix { $0 != ":" }) }

    public var host: String { components?.host ?? "" }

    /// `nil` for the scheme's default port.
    public var port: Int? { components?.port }

    private var components: URLComponents? { URLComponents(string: rawValue) }

    /// The origin of `address`, with a Unicode host in its ASCII form; `nil` unless it is HTTP(S).
    public init?(address: String) {
        guard let components = URLComponents(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme, let host = components.encodedHost else { return nil }
        self.init(scheme: scheme, host: host, port: components.port)
    }
}
