import Foundation

/// The registrable domain of a host ("example.com" for "accounts.example.com"), from the Public
/// Suffix List's rules. See docs/PASSWORDS.md › Matching sites.
public struct PublicSuffixList: Sendable {
    private let rules: Set<String>
    private let wildcards: Set<String>
    private let exceptions: Set<String>

    /// `rules` is the list's text: one rule per line, `//` comments, `*.` wildcards and `!` exceptions.
    /// Rules in Unicode are compared in their ASCII form, as hosts arrive from WebKit.
    public init(rules text: String) {
        var rules = Set<String>(), wildcards = Set<String>(), exceptions = Set<String>()
        for line in text.split(whereSeparator: \.isNewline) {
            guard let token = line.split(whereSeparator: \.isWhitespace).first, !token.hasPrefix("//") else { continue }
            var rule = String(token).lowercased()
            if !rule.allSatisfy(\.isASCII) { rule = Self.ascii(rule) }
            if rule.hasPrefix("!") { exceptions.insert(String(rule.dropFirst())) }
            else if rule.hasPrefix("*.") { wildcards.insert(String(rule.dropFirst(2))) }
            else { rules.insert(rule) }
        }
        self.rules = rules
        self.wildcards = wildcards
        self.exceptions = exceptions
    }

    /// `nil` for a public suffix itself, a single label such as `localhost`, and IP addresses.
    public func registrableDomain(of host: String) -> String? {
        var host = host.lowercased()
        if host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty, !host.contains(":"), !host.hasPrefix("["), !Self.isIPv4(host) else { return nil }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard !labels.contains(where: \.isEmpty) else { return nil }
        // The prevailing rule: an exception if one matches, else the longest match, else "*".
        var suffixLength = 1
        for index in labels.indices {
            let candidate = labels[index...].joined(separator: ".")
            let length = labels.count - index
            if exceptions.contains(candidate) { suffixLength = length - 1; break }
            if rules.contains(candidate) { suffixLength = max(suffixLength, length) }
            if index + 1 < labels.count, wildcards.contains(labels[(index + 1)...].joined(separator: ".")) {
                suffixLength = max(suffixLength, length)
            }
        }
        guard labels.count > suffixLength else { return nil }
        return labels.suffix(suffixLength + 1).joined(separator: ".")
    }

    private static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }

    /// Foundation turns a Unicode host into its ASCII (Punycode) form when it parses an address.
    private static func ascii(_ rule: String) -> String {
        let prefix = rule.hasPrefix("!") ? "!" : rule.hasPrefix("*.") ? "*." : ""
        let name = String(rule.dropFirst(prefix.count))
        return prefix + (URLComponents(string: "https://\(name)")?.encodedHost ?? name)
    }
}
