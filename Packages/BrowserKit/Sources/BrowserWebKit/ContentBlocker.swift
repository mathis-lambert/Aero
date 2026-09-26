import BrowserCore
import CryptoKit
import Foundation
import os
import WebKit

/// Ad and tracker blocking with WebKit content rule lists. The lists are compiled once per content,
/// in a store kept between launches, and added to or removed from each page before it navigates.
/// See docs/SITE_CONTROLS.md › Ad and tracker blocking.
@MainActor
public final class ContentBlocker {
    public enum Failure: Error { case compilationFailed }

    private static let logger = Logger(subsystem: Diagnostics.subsystem, category: Diagnostics.Category.contentBlocking)
    private static let identifierPrefix = "filters-"

    private let store: WKContentRuleListStore
    private var lists: [WKContentRuleList] = [] {
        didSet { generation += 1 }
    }
    private var generation = 0
    private var installation: Task<Void, any Error>?
    /// Called once new lists are in use, so open pages can take them.
    var onInstall: (() -> Void)?

    public init?(directory: URL) {
        guard let store = WKContentRuleListStore(url: directory) else { return nil }
        self.store = store
    }

    /// Uses the rules of `sources`, compiling them unless the store already has them. The lists in
    /// use stay until the new ones are all compiled, and stay for good if one fails.
    public func install(_ sources: [FilterList]) async throws {
        let previous = installation
        let task = Task { [store] in
            _ = try? await previous?.value
            let stamp = Self.stamp(of: sources)
            if let installed = try await Self.lookUp(stamp: stamp, in: store) { self.lists = installed }
            else { self.lists = try await Self.compile(sources, stamp: stamp, in: store) }
            self.onInstall?()
            await Self.removeLists(except: stamp, from: store)
        }
        installation = task
        try await task.value
    }

    /// What `apply` puts on a page: the current lists, or none; a page holding it has nothing to update.
    func state(enabled: Bool) -> Int { enabled ? generation : -1 }

    func apply(to controller: WKUserContentController, enabled: Bool) {
        controller.removeAllContentRuleLists()
        if enabled { lists.forEach(controller.add) }
    }

    /// Identifiers are `filters-<stamp>-<index>-<count>`, so a partial set is never taken for a whole one.
    private static func lookUp(stamp: String, in store: WKContentRuleListStore) async throws -> [WKContentRuleList]? {
        let identifiers = (await store.availableIdentifiers() ?? []).filter { $0.hasPrefix(identifierPrefix + stamp + "-") }.sorted()
        guard let count = identifiers.first?.split(separator: "-").last.flatMap({ Int($0) }), identifiers.count == count else { return nil }
        var lists: [WKContentRuleList] = []
        for identifier in identifiers {
            guard let list = try await store.contentRuleList(forIdentifier: identifier) else { return nil }
            lists.append(list)
        }
        return lists
    }

    private static func compile(_ sources: [FilterList], stamp: String, in store: WKContentRuleListStore) async throws -> [WKContentRuleList] {
        let texts = sources.map(\.text)
        let conversion = await Task.detached(priority: .utility) { FilterListConverter.convert(texts) }.value
        logger.info("Converted \(conversion.ruleCount) rules, skipped \(conversion.skippedCount)")
        var lists: [WKContentRuleList] = []
        for (index, json) in conversion.lists.enumerated() {
            let identifier = "\(identifierPrefix)\(stamp)-\(index)-\(conversion.lists.count)"
            guard let list = try await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) else {
                throw Failure.compilationFailed
            }
            lists.append(list)
        }
        return lists
    }

    private static func removeLists(except stamp: String, from store: WKContentRuleListStore) async {
        for identifier in await store.availableIdentifiers() ?? [] where !identifier.hasPrefix(identifierPrefix + stamp + "-") {
            // Best effort: a stale list only takes disk space until the next installation.
            try? await store.removeContentRuleList(forIdentifier: identifier)
        }
    }

    /// The sources and the converter's version, so either changing rebuilds the lists.
    private static func stamp(of sources: [FilterList]) -> String {
        var hash = SHA256()
        hash.update(data: Data("\(FilterListConverter.version)".utf8))
        for source in sources { hash.update(data: Data(source.text.utf8)) }
        return hash.finalize().prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
