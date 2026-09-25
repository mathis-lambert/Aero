import Foundation

/// A browser page drawn natively in a tab, addressed as `aero://<page>`.
/// Websites can never navigate to these addresses; only the browser opens them.
public enum InternalPage: String, CaseIterable, Sendable {
    case history

    public static let scheme = "aero"

    public init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, let host = url.host?.lowercased(), let page = Self(rawValue: host) else { return nil }
        self = page
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = rawValue
        guard let url = components.url else { preconditionFailure("Invalid internal page \(rawValue)") }
        return url
    }
}
