import Foundation

/// How Aero names itself to websites and extensions.
public enum BrowserIdentity {
    /// Safari's user agent suffix. Without it, sites such as Google see an unknown WebKit browser and serve their basic,
    /// legacy pages, and extensions that read the user agent to choose their code, such as Bitwarden, do not start.
    /// The installed Safari's version matches the system's engine.
    public static let applicationNameForUserAgent = "Version/\(safariVersion) Safari/605.1.15"

    private static var safariVersion: String {
        ["/System/Cryptexes/App/System/Applications/Safari.app", "/Applications/Safari.app"].lazy
            .compactMap { Bundle(path: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String }
            .first ?? "27.0"
    }
}
