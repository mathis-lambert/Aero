import Foundation

/// A device a site may ask for. See docs/BROWSING.md › Site data and permissions.
public enum SitePermission: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable {
    case camera, microphone, location
}

/// A saved answer; a permission without one asks every time.
public enum SiteDecision: String, Codable, Sendable {
    case allow, block
}

/// A web origin in one form, `scheme://host[:port]`: lowercased, without the scheme's default
/// port, so a decision matches however the address was written.
public struct SiteOrigin: RawRepresentable, Hashable, Codable, CodingKeyRepresentable, Sendable {
    private static let defaultPorts = ["http": 80, "https": 443]

    public let rawValue: String

    public init?(scheme: String, host: String, port: Int?) {
        let scheme = scheme.lowercased()
        let host = host.lowercased()
        guard let defaultPort = Self.defaultPorts[scheme], !host.isEmpty else { return nil }
        let port = port.flatMap { $0 == 0 || $0 == defaultPort ? nil : $0 }
        rawValue = "\(scheme)://\(host)" + (port.map { ":\($0)" } ?? "")
    }

    public init?(url: URL) {
        guard let scheme = url.scheme, let host = url.host() else { return nil }
        self.init(scheme: scheme, host: host, port: url.port)
    }

    /// Only the canonical form is accepted, so a saved session never holds two keys for one origin.
    public init?(rawValue: String) {
        guard let url = URL(string: rawValue), let origin = SiteOrigin(url: url), origin.rawValue == rawValue else { return nil }
        self = origin
    }
}
