import Foundation

/// Converts Adblock Plus lists (EasyList, EasyPrivacy) into WebKit content rule lists. Rules WebKit
/// cannot enforce natively are skipped, never approximated. See docs/SITE_CONTROLS.md › Ad and tracker blocking.
package enum FilterListConverter {
    /// Changes whenever the output for the same lists changes, so compiled lists are rebuilt.
    package static let version = 1
    /// WebKit refuses a list with more rules.
    package static let maximumRulesPerList = 150_000

    /// Each list is JSON ready to compile; together they hold every converted rule.
    package static func convert(_ lists: [String], maximumRulesPerList: Int = maximumRulesPerList) -> FilterConversion {
        let rules = FilterRules(list: lists.joined(separator: "\n"))
        let encoder = JSONEncoder()
        // An exception only undoes rules before it in its own list, so every chunk carries its exceptions.
        let groups: [(rules: [ContentRule], exceptions: [ContentRule])] = [
            (rules[.networkBlock], rules[.networkException] + rules[.documentException]),
            (rules[.genericHiding], rules[.genericHideException] + rules[.elementHideException] + rules[.documentException]),
            (rules[.domainHiding], rules[.elementHideException] + rules[.documentException])
        ]
        let lists = groups.flatMap { group -> [[ContentRule]] in
            let size = max(1, maximumRulesPerList - group.exceptions.count)
            return stride(from: 0, to: group.rules.count, by: size).map { Array(group.rules[$0..<min($0 + size, group.rules.count)]) + group.exceptions }
        }
        return FilterConversion(
            lists: lists.compactMap { (try? encoder.encode($0)).map { String(decoding: $0, as: UTF8.self) } },
            ruleCount: rules.count,
            skippedCount: rules.skippedCount
        )
    }
}

package struct FilterConversion: Sendable {
    package let lists: [String]
    package let ruleCount: Int
    /// Rules in a syntax WebKit cannot enforce natively.
    package let skippedCount: Int
}

/// The converted rules of a list, by the order they must keep: an exception follows what it undoes.
struct FilterRules {
    enum Stage: CaseIterable {
        case networkBlock, networkException, genericHiding, genericHideException, domainHiding, elementHideException, documentException
    }

    private(set) var skippedCount = 0
    private(set) var count = 0
    private var rules: [Stage: [ContentRule]] = [:]
    private var genericSelectors: [(selector: String, excluded: [String])] = []
    private var domainSelectors: [(selector: String, domains: [String])] = []
    /// Selectors a `#@#` rule allows on some domains, or everywhere when the set is empty.
    private var allowedSelectors: [String: Set<String>] = [:]

    init(list: String) {
        for line in list.split(whereSeparator: \.isNewline) {
            let line = line.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("!"), !line.hasPrefix("[Adblock") else { continue }
            if !add(line) { skippedCount += 1 }
        }
        // Hiding rules are built last: a `#@#` exception may come after the rule it narrows.
        rules[.genericHiding] = genericHiding()
        rules[.domainHiding] = domainHiding()
        count = rules.values.reduce(0) { $0 + $1.count }
    }

    subscript(stage: Stage) -> [ContentRule] { rules[stage] ?? [] }

    private func genericHiding() -> [ContentRule] {
        genericSelectors.compactMap { selector, excluded in
            let allowed = allowedSelectors[selector]
            guard allowed?.isEmpty != true else { return nil }
            let unless = Self.wildcarded(excluded + (allowed ?? []).sorted())
            return ContentRule(trigger: .init(urlFilter: ".*", unlessDomain: unless.isEmpty ? nil : unless), action: .init(type: .cssDisplayNone, selector: selector))
        }
    }

    private func domainHiding() -> [ContentRule] {
        domainSelectors.compactMap { selector, domains in
            let allowed = allowedSelectors[selector]
            guard allowed?.isEmpty != true else { return nil }
            let kept = domains.filter { allowed?.contains($0) != true }
            guard !kept.isEmpty else { return nil }
            return ContentRule(trigger: .init(urlFilter: ".*", ifDomain: Self.wildcarded(kept)), action: .init(type: .cssDisplayNone, selector: selector))
        }
    }

    // MARK: - Element hiding

    private static let unsupportedCosmeticSeparators = ["#?#", "#@?#", "#$#", "#@$#", "#%#", "#@%#"]
    /// Adblock Plus and uBlock pseudo-classes no browser's CSS understands.
    private static let extendedPseudoClasses = [
        ":-abp-", ":has-text(", ":contains(", ":xpath(", ":matches-css", ":upward(", ":remove(", ":style(",
        ":min-text-length(", ":watch-attr(", ":matches-path(", ":matches-attr(", ":matches-prop", ":others(", ":if(", ":if-not("
    ]

    private mutating func add(_ line: String) -> Bool {
        if Self.unsupportedCosmeticSeparators.contains(where: line.contains) { return false }
        if let range = line.range(of: "#@#") { return addHiding(domains: line[..<range.lowerBound], selector: line[range.upperBound...], allowed: true) }
        if let range = line.range(of: "##") { return addHiding(domains: line[..<range.lowerBound], selector: line[range.upperBound...], allowed: false) }
        return addNetwork(line)
    }

    private mutating func addHiding(domains list: Substring, selector: Substring, allowed: Bool) -> Bool {
        let selector = selector.trimmingCharacters(in: .whitespaces)
        guard !selector.isEmpty, !selector.hasPrefix("+js("), !Self.extendedPseudoClasses.contains(where: selector.contains),
              let (included, excluded) = Self.domains(list.split(separator: ",").map(String.init)) else { return false }
        if allowed {
            guard excluded.isEmpty else { return false }
            if included.isEmpty { allowedSelectors[selector] = [] }
            else if allowedSelectors[selector]?.isEmpty != true { allowedSelectors[selector, default: []].formUnion(included) }
        } else if included.isEmpty {
            genericSelectors.append((selector, excluded))
        } else {
            guard excluded.isEmpty else { return false }
            domainSelectors.append((selector, included))
        }
        return true
    }

    // MARK: - Network rules

    /// A rule is one of these; the most specific exception option wins.
    private enum Exception: Int, Comparable {
        case none, request, genericHide, elementHide, document

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    private static let exceptionOptions: [String: Exception] = [
        "document": .document, "doc": .document, "elemhide": .elementHide, "ehide": .elementHide, "generichide": .genericHide, "ghide": .genericHide
    ]

    /// Adblock Plus resource types and their uBlock aliases, as WebKit names them. `document` stands
    /// for frames too: WebKit has no separate subdocument type.
    private static let resourceTypes = [
        "script": "script", "image": "image", "stylesheet": "style-sheet", "css": "style-sheet", "font": "font", "media": "media",
        "xmlhttprequest": "fetch", "xhr": "fetch", "subdocument": "document", "frame": "document", "ping": "ping",
        "websocket": "websocket", "popup": "popup", "other": "other"
    ]
    /// What a negated type list starts from: every subresource, not the page itself or its popups.
    private static let subresourceTypes = ["script", "image", "style-sheet", "font", "media", "fetch", "document", "ping", "websocket", "other"]
    private static let unsupportedTypes: Set = ["object", "object-subrequest", "webrtc"]

    private mutating func addNetwork(_ line: String) -> Bool {
        var pattern = Substring(line)
        let isException = pattern.hasPrefix("@@")
        if isException { pattern = pattern.dropFirst(2) }
        var options: [Substring] = []
        if let dollar = pattern.lastIndex(of: "$"), Self.looksLikeOptions(pattern[pattern.index(after: dollar)...]) {
            options = pattern[pattern.index(after: dollar)...].split(separator: ",")
            pattern = pattern[..<dollar]
        }
        if pattern.count > 1, pattern.hasPrefix("/"), pattern.hasSuffix("/") { return false }
        guard pattern.allSatisfy(\.isASCII), let urlFilter = Self.regex(for: pattern) else { return false }

        var trigger = ContentRule.Trigger(urlFilter: urlFilter)
        var included: [String] = [], excluded: Set<String> = []
        var droppedType = false
        var exception = isException ? Exception.request : .none
        for option in options {
            let negated = option.hasPrefix("~")
            let parts = option.dropFirst(negated ? 1 : 0).split(separator: "=", maxSplits: 1)
            let name = parts.first.map(String.init) ?? ""
            switch name {
            case "third-party", "3p": trigger.loadType = [negated ? "first-party" : "third-party"]
            case "first-party", "1p": trigger.loadType = [negated ? "third-party" : "first-party"]
            case "match-case": trigger.urlFilterIsCaseSensitive = true
            case "important": continue
            case "domain":
                guard !negated, parts.count == 2, let (ifDomain, unlessDomain) = Self.domains(parts[1].split(separator: "|").map(String.init)),
                      ifDomain.isEmpty || unlessDomain.isEmpty else { return false }
                trigger.ifDomain = ifDomain.isEmpty ? nil : Self.wildcarded(ifDomain)
                trigger.unlessDomain = unlessDomain.isEmpty ? nil : Self.wildcarded(unlessDomain)
            default:
                if let kind = Self.exceptionOptions[name] {
                    guard !negated else { return false }
                    if isException { exception = max(exception, kind) }
                    else if kind == .document { included.append("document") }
                    else { return false }
                } else if let type = Self.resourceTypes[name] {
                    if negated { excluded.insert(type) } else { included.append(type) }
                } else if Self.unsupportedTypes.contains(name) {
                    if !negated { droppedType = true }
                } else {
                    return false
                }
            }
        }
        let types = included.isEmpty ? Self.subresourceTypes.filter { !excluded.contains($0) } : Self.unique(included.filter { !excluded.contains($0) })
        // Without a supported type left, the rule would otherwise widen into every type.
        if !included.isEmpty || !excluded.isEmpty || droppedType {
            guard !types.isEmpty, !(included.isEmpty && droppedType) else { return false }
            trigger.resourceType = types
        }

        switch exception {
        case .none: append(trigger, .block, to: .networkBlock)
        case .request: append(trigger, .ignorePreviousRules, to: .networkException)
        case .document:
            guard trigger.ifDomain == nil, trigger.unlessDomain == nil else { return false }
            append(ContentRule.Trigger(urlFilter: ".*", ifTopURL: [trigger.urlFilter]), .ignorePreviousRules, to: .documentException)
        case .elementHide, .genericHide:
            trigger.resourceType = ["document"]
            append(trigger, .ignorePreviousRules, to: exception == .elementHide ? .elementHideException : .genericHideException)
        }
        return true
    }

    private mutating func append(_ trigger: ContentRule.Trigger, _ action: ContentRule.Action.Kind, to stage: Stage) {
        rules[stage, default: []].append(ContentRule(trigger: trigger, action: .init(type: action)))
    }

    private static func looksLikeOptions(_ text: Substring) -> Bool {
        guard let first = text.split(separator: ",").first else { return false }
        return first.drop { $0 == "~" }.prefix { $0 != "=" }.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    // MARK: - Patterns

    private static let domainAnchor = "^[a-zA-Z][a-zA-Z0-9+.-]*://([^/?#]*\\.)?"
    /// Adblock Plus's `^`: any character but a letter, a digit or `_-.%`.
    private static let separator = "[^a-zA-Z0-9_.%-]"
    private static let regexSpecials: Set<Character> = [".", "+", "?", "(", ")", "[", "]", "{", "}", "\\", "$", "|", "/"]

    /// The pattern as WebKit's regular expression subset. It has no alternation, so a trailing
    /// separator, which may also be the end of the address, becomes an optional group before the end.
    /// After a bare domain the address always goes on (a port or a path), and the group is left
    /// out: across a list of domains it makes WebKit's compilation ten times slower.
    static func regex(for pattern: Substring) -> String? {
        var body = pattern
        var prefix = ""
        var suffix = ""
        if body.hasPrefix("||") { body = body.dropFirst(2); prefix = domainAnchor }
        else if body.hasPrefix("|") { body = body.dropFirst(); prefix = "^" }
        if body.hasSuffix("|") { body = body.dropLast(); suffix = "$" }
        if suffix.isEmpty, body.hasSuffix("^") {
            body = body.dropLast()
            let bareDomain = prefix == domainAnchor && !body.contains { "/*^?=&:".contains($0) }
            suffix = bareDomain ? separator : "(\(separator).*)?$"
        }
        if prefix.isEmpty { body = body.drop { $0 == "*" } }
        if suffix.isEmpty { while body.hasSuffix("*") { body = body.dropLast() } }
        if body.contains("|") { return nil }
        var regex = prefix
        for character in body {
            switch character {
            case "*": regex += ".*"
            case "^": regex += separator
            case _ where regexSpecials.contains(character): regex += "\\\(character)"
            default: regex.append(character)
            }
        }
        regex += suffix
        return regex.isEmpty ? ".*" : regex
    }

    // MARK: - Domains

    /// Splits `example.com` and `~example.com` entries; `nil` for one a trigger cannot hold, such as `example.*`.
    private static func domains(_ entries: [String]) -> (included: [String], excluded: [String])? {
        var included: [String] = [], excluded: [String] = []
        for entry in entries where !entry.isEmpty {
            let negated = entry.hasPrefix("~")
            let domain = entry.dropFirst(negated ? 1 : 0).lowercased()
            guard !domain.isEmpty, domain.allSatisfy({ ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "." || $0 == "-" }),
                  !domain.hasPrefix("."), !domain.hasSuffix(".") else { return nil }
            if negated { excluded.append(domain) } else { included.append(domain) }
        }
        return (included, excluded)
    }

    /// WebKit matches a domain alone unless it starts with `*`, which also covers its subdomains.
    private static func wildcarded(_ domains: [String]) -> [String] { unique(domains).map { "*" + $0 } }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }
}
