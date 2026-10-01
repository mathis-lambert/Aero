import WebKit

/// Chrome's host permissions cover websites, never another extension's pages.
@MainActor
enum ExtensionSiteAccess {
    static func isExtensionScheme(_ scheme: String?) -> Bool {
        ["chrome-extension", "webkit-extension"].contains(scheme?.lowercased() ?? "")
    }

    static func permits(_ pattern: WKWebExtension.MatchPattern) -> Bool {
        !isExtensionScheme(pattern.scheme)
    }

    static func restore(_ sites: [String], on context: WKWebExtensionContext) throws {
        var grants: [WKWebExtension.MatchPattern: Date] = [:]
        for site in sites {
            let pattern = try WKWebExtension.MatchPattern(string: site)
            if permits(pattern) { grants[pattern] = .distantFuture }
        }
        context.grantedPermissionMatchPatterns = grants
        try restrict(context)
    }

    // Registered custom schemes participate in WebKit's <all_urls>. Explicit denials
    // keep those broad website grants from exposing another extension's pages.
    static func restrict(_ context: WKWebExtensionContext) throws {
        for scheme in ["chrome-extension", "webkit-extension"] {
            let pattern = try WKWebExtension.MatchPattern(string: "\(scheme)://*/*")
            context.setPermissionStatus(.deniedExplicitly, for: pattern)
        }
    }
}
