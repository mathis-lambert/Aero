import Foundation

/// One WebKit content blocking rule, in the JSON form `WKContentRuleListStore` compiles.
struct ContentRule: Codable, Equatable, Sendable {
    struct Trigger: Codable, Equatable, Sendable {
        var urlFilter: String
        var urlFilterIsCaseSensitive: Bool?
        var resourceType: [String]?
        var loadType: [String]?
        var ifDomain: [String]?
        var unlessDomain: [String]?
        var ifTopURL: [String]?

        private enum CodingKeys: String, CodingKey {
            case urlFilter = "url-filter", urlFilterIsCaseSensitive = "url-filter-is-case-sensitive", resourceType = "resource-type"
            case loadType = "load-type", ifDomain = "if-domain", unlessDomain = "unless-domain", ifTopURL = "if-top-url"
        }
    }

    struct Action: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Sendable {
            case block, cssDisplayNone = "css-display-none", ignorePreviousRules = "ignore-previous-rules"
        }

        var type: Kind
        var selector: String?
    }

    var trigger: Trigger
    var action: Action
}

/// A downloaded or bundled Adblock Plus list, recognized by its header. A response without one,
/// such as an error page, is not a list.
public struct FilterList: Sendable {
    public let text: String
    /// The list's `! Version:` stamp, such as 202609261023; a larger one is newer.
    public let version: Int

    public init?(text: String) {
        guard text.hasPrefix("[Adblock Plus") else { return nil }
        let header = text.prefix(4096).split(whereSeparator: \.isNewline).prefix { $0.hasPrefix("!") || $0.hasPrefix("[") }
        guard let line = header.first(where: { $0.hasPrefix("! Version:") }),
              let version = Int(line.dropFirst("! Version:".count).trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        self.text = text
        self.version = version
    }
}
