import BrowserCore
import Foundation

/// Safari's adapter: one space with its favorites and history, readable with Full Disk Access. Its passwords stay in
/// the Passwords app; its icons are fetched again by Aero, since Safari's icon cache is private.
enum SafariImport {
    static func read(root: URL, limits: ImportLimits) throws -> [ImportedProfile] {
        var space = try SafariBookmarks.read(SourceFiles.data(root.appendingPathComponent("Bookmarks.plist")), limits: limits)
        space.name = "Safari"
        let history = (try? SafariHistory.read(root.appendingPathComponent("History.db"), limits: limits)) ?? ImportedHistory()
        return [ImportedProfile(id: root.path, name: "Safari", spaces: [space], history: history)]
    }
}

enum SafariBookmarks {
    private static let bar = "BookmarksBar", menu = "BookmarksMenu", readingList = "com.apple.ReadingList"
    private static let leaf = "WebBookmarkTypeLeaf", list = "WebBookmarkTypeList"

    /// Safari's `Bookmarks.plist`: the Favorites bar's links are favorites and each of its folders a group; the
    /// Bookmarks menu is one group; other top-level folders are groups; the Reading List is left out. Folders inside
    /// a group are gathered in it, in order.
    static func read(_ data: Data, limits: ImportLimits) throws -> ImportedSpace {
        guard let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let top = root["Children"] as? [[String: Any]] else { throw BrowserImportError.unreadable }
        var collector = LinkCollector(limit: limits.links)
        for node in top {
            switch (node["WebBookmarkType"] as? String, node["Title"] as? String) {
            case (list, bar):
                for child in children(of: node) {
                    switch child["WebBookmarkType"] as? String {
                    case leaf: collector.addLink(link(child, into: &collector))
                    case list: gather(children(of: child), into: collector.newGroup(.folder(title(child))), collector: &collector)
                    default: continue
                    }
                }
            case (list, menu): gather(children(of: node), into: collector.newGroup(.bookmarksMenu), collector: &collector)
            case (list, readingList): continue
            case (list, _): gather(children(of: node), into: collector.newGroup(.folder(title(node))), collector: &collector)
            case (leaf, _): collector.addLink(link(node, into: &collector))
            default: continue
            }
        }
        return collector.finished()
    }

    private static func children(of node: [String: Any]) -> [[String: Any]] { (node["Children"] as? [[String: Any]]) ?? [] }
    private static func title(_ node: [String: Any]) -> String { (node["Title"] as? String) ?? "" }

    private static func gather(_ nodes: [[String: Any]], into group: Int, collector: inout LinkCollector) {
        for node in nodes {
            switch node["WebBookmarkType"] as? String {
            case leaf: collector.add(link(node, into: &collector), toGroup: group)
            case list: gather(children(of: node), into: group, collector: &collector)
            default: continue
            }
        }
    }

    private static func link(_ node: [String: Any], into collector: inout LinkCollector) -> ImportedLink? {
        let title = ((node["URIDictionary"] as? [String: Any])?["title"] as? String) ?? ""
        return collector.link((node["URLString"] as? String) ?? "", title: title)
    }
}

enum SafariHistory {
    /// Safari's `History.db`: visit times are seconds since 2001; a page's title is its latest visit's.
    static func read(_ file: URL, limits: ImportLimits) throws -> ImportedHistory {
        try SourceFiles.database(file) { database in
            let rows = try database.query("""
                SELECT history_items.url, history_visits.visit_time, history_visits.title
                FROM history_visits JOIN history_items ON history_items.id = history_visits.history_item
                WHERE history_visits.visit_time >= ? ORDER BY history_visits.visit_time DESC
                """, [.real(limits.since.timeIntervalSinceReferenceDate)]) { (address: $0.text(0), time: $0.real(1), title: $0.text(2)) }
            var order: [(address: String, url: URL)] = [], pages: [String: (title: String, visits: [Date])] = [:], skipped = Set<String>()
            for row in rows {
                if var page = pages[row.address] {
                    if page.visits.count < limits.visitsPerPage { page.visits.append(Date(timeIntervalSinceReferenceDate: row.time)); pages[row.address] = page }
                    continue
                }
                guard !skipped.contains(row.address) else { continue }
                guard let url = URL(string: row.address), NavigationInput.isWebURL(url) else { skipped.insert(row.address); continue }
                guard order.count < limits.pages else { continue }
                order.append((row.address, url))
                pages[row.address] = (row.title, [Date(timeIntervalSinceReferenceDate: row.time)])
            }
            let result = order.compactMap { entry -> ImportedPage? in
                guard let page = pages[entry.address], let last = page.visits.first else { return nil }
                return ImportedPage(url: entry.url, title: page.title, lastVisit: last, visits: page.visits)
            }
            return ImportedHistory(pages: result, skipped: skipped.count)
        }
    }
}
