import Foundation
import WebKit

/// Website returns may enter only resources the extension declares public to that origin.
enum ExtensionResources {
    @MainActor
    static func allows(_ target: URL, from origin: URL, context: WKWebExtensionContext) -> Bool {
        guard target.scheme == context.baseURL.scheme, target.host() == context.baseURL.host(),
              target.port == nil, target.user == nil, target.password == nil,
              ["http", "https"].contains(origin.scheme?.lowercased() ?? ""),
              let components = URLComponents(url: target, resolvingAgainstBaseURL: false) else { return false }
        let encoded = components.percentEncodedPath.lowercased()
        guard !encoded.contains("%2f"), !encoded.contains("%5c"),
              let path = components.percentEncodedPath.removingPercentEncoding,
              !path.contains("\\"), !path.contains("%"),
              !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              !path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { return false }
        let resource = String(path.dropFirst())
        guard !resource.isEmpty else { return false }
        let manifest = context.webExtension.manifest
        if (manifest["manifest_version"] as? Int) == 2 {
            return (manifest["web_accessible_resources"] as? [String] ?? []).contains { matches(resource, pattern: $0) }
        }
        return (manifest["web_accessible_resources"] as? [[String: Any]] ?? []).contains { rule in
            guard rule["use_dynamic_url"] as? Bool != true,
                  let resources = rule["resources"] as? [String], let origins = rule["matches"] as? [String],
                  resources.contains(where: { matches(resource, pattern: $0) }) else { return false }
            return origins.contains { pattern in
                guard let match = try? WKWebExtension.MatchPattern(string: pattern) else { return false }
                return match.matches(origin, options: .ignorePaths)
            }
        }
    }

    private static func matches(_ resource: String, pattern: String) -> Bool {
        let expression = "\\A" + pattern.trimmingCharacters(in: CharacterSet(charactersIn: "/")).components(separatedBy: "*")
            .map(NSRegularExpression.escapedPattern(for:)).joined(separator: ".*") + "\\z"
        return resource.range(of: expression, options: .regularExpression) != nil
    }
}
