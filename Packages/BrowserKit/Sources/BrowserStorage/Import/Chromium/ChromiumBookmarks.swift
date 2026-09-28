import Foundation

/// A Chromium profile's `Bookmarks` file.
enum ChromiumBookmarks {
    /// The bar's links are favorites and each of its folders a group; the other and mobile bookmarks are one group
    /// each. Folders inside a group are gathered in it, in order.
    static func read(_ data: Data, limits: ImportLimits) throws -> ImportedSpace {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let roots = root["roots"] as? [String: Any] else {
            throw BrowserImportError.unreadable
        }
        var collector = LinkCollector(limit: limits.links)
        for node in children(of: roots["bookmark_bar"]) {
            switch node["type"] as? String {
            case "url": collector.addLink(link(node, into: &collector))
            case "folder":
                let group = collector.newGroup(.folder((node["name"] as? String) ?? ""))
                gather(children(of: node), into: group, collector: &collector)
            default: continue
            }
        }
        for (key, title) in [("other", ImportedGroup.Title.otherBookmarks), ("synced", .mobileBookmarks)] {
            let group = collector.newGroup(title)
            gather(children(of: roots[key]), into: group, collector: &collector)
        }
        return collector.finished()
    }

    private static func children(of node: Any?) -> [[String: Any]] {
        ((node as? [String: Any])?["children"] as? [[String: Any]]) ?? []
    }

    private static func gather(_ nodes: [[String: Any]], into group: Int, collector: inout LinkCollector) {
        for node in nodes {
            switch node["type"] as? String {
            case "url": collector.add(link(node, into: &collector), toGroup: group)
            case "folder": gather(children(of: node), into: group, collector: &collector)
            default: continue
            }
        }
    }

    private static func link(_ node: [String: Any], into collector: inout LinkCollector) -> ImportedLink? {
        collector.link((node["url"] as? String) ?? "", title: (node["name"] as? String) ?? "")
    }
}
