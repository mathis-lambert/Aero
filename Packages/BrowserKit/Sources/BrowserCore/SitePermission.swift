import Foundation

/// What a site may do: use a device, show ads and trackers, or have its video moved to picture in
/// picture. See docs/SITE_CONTROLS.md › Site data and permissions.
public enum SitePermission: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable {
    case camera, microphone, location, ads, automaticPictureInPicture

    /// Devices ask every time without a decision; the others follow a browser-wide setting.
    public var isDevice: Bool {
        switch self {
        case .camera, .microphone, .location: true
        case .ads, .automaticPictureInPicture: false
        }
    }
}

public enum SiteDecision: String, Codable, Sendable {
    case allow, block
}

/// A web origin in one form, `scheme://host[:port]`: lowercased, without the scheme's default
/// port, so a decision matches however the address was written.
public struct SiteOrigin: RawRepresentable, Hashable, Codable, CodingKeyRepresentable, Sendable {
    private static let defaultPorts = ["http": 80, "https": 443]

    public let rawValue: String

    package init?(scheme: String, host: String, port: Int?) {
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
