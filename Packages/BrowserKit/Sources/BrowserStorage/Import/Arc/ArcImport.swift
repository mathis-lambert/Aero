import BrowserCore
import Foundation

/// Arc's adapter: spaces, pinned tabs, folders and favorites from its sidebar file; history, passwords and icons from
/// the Chromium profile each space uses (`ChromiumImport`). See docs/ONBOARDING.md › Sources.
enum ArcImport {
    static let sidebarFile = "StorableSidebar.json"

    /// `root` is Arc's user data folder; the sidebar file is beside it.
    static func read(browser: ChromiumBrowser, root: URL, profiles: [ChromiumProfile], limits: ImportLimits) throws -> [ImportedProfile] {
        let sidebar = try ArcSidebar.read(SourceFiles.data(root.deletingLastPathComponent().appendingPathComponent(sidebarFile)), limits: limits)
        var order: [String] = [], spaces: [String: [ImportedSpace]] = [:]
        for entry in sidebar.spaces {
            if spaces[entry.profileFolder] == nil { order.append(entry.profileFolder) }
            spaces[entry.profileFolder, default: []].append(entry.space)
        }
        return order.map { folder in
            // A space may use a profile whose folder holds none of the files that list profiles.
            let profile = profiles.first { $0.folderName == folder } ?? browser.profile(named: folder, in: root)
            return ChromiumImport.imported(profile, spaces: spaces[folder] ?? [], limits: limits)
        }
    }
}

struct ArcSidebar {
    struct Space { let profileFolder: String; var space: ImportedSpace }
    var spaces: [Space]

    /// Arc's `StorableSidebar.json`: each space's pinned tabs and first-level folders, and each profile's favorites.
    static func read(_ data: Data, limits: ImportLimits) throws -> ArcSidebar {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let containers = (root["sidebar"] as? [String: Any])?["containers"] as? [Any],
              let main = containers.compactMap({ $0 as? [String: Any] }).first(where: { $0["spaces"] != nil }),
              let spaceRecords = main["spaces"] as? [Any], let itemRecords = main["items"] as? [Any] else {
            throw BrowserImportError.unreadable
        }
        // Records interleave identifiers and dictionaries; only the dictionaries matter.
        var items: [String: [String: Any]] = [:]
        for case let item as [String: Any] in itemRecords { if let id = item["id"] as? String { items[id] = item } }
        let reader = Reader(items: items)

        var result = ArcSidebar(spaces: [])
        for case let record as [String: Any] in spaceRecords {
            var collector = LinkCollector(limit: limits.links)
            if let pinned = container(named: "pinned", in: record["containerIDs"]) { reader.collectPinned(pinned, into: &collector) }
            var space = collector.finished()
            space.name = record["title"] as? String
            space.color = color(record)
            space.emoji = emoji(record)
            space.position = result.spaces.count
            result.spaces.append(Space(profileFolder: profileFolder(record["profile"]), space: space))
        }
        // Favorites: pairs of a profile marker and a container. Arc shows them above every space of that profile.
        if let top = main["topAppsContainerIDs"] as? [Any] {
            for index in stride(from: 0, to: top.count - 1, by: 2) {
                guard let id = top[index + 1] as? String else { continue }
                var collector = LinkCollector(limit: limits.links)
                for child in reader.children(of: id) { collector.addTile(reader.tab(child, into: &collector)) }
                let tiles = collector.finished().tiles
                let folder = profileFolder(top[index])
                for target in result.spaces.indices where result.spaces[target].profileFolder == folder {
                    let pinned = Set(result.spaces[target].space.allLinks.map(\.url))
                    result.spaces[target].space.tiles = tiles.filter { !pinned.contains($0.url) }
                }
            }
        }
        return result
    }

    private struct Reader {
        let items: [String: [String: Any]]

        func children(of id: String) -> [[String: Any]] {
            ((items[id]?["childrenIds"] as? [String]) ?? []).compactMap { items[$0] }
        }

        private func kind(_ item: [String: Any]) -> String? { (item["data"] as? [String: Any])?.keys.first }

        /// Loose tabs are rows; each first-level folder is a group gathering everything nested in it; a split view
        /// gives its tabs. Documents and the welcome page are not websites and are left out.
        func collectPinned(_ container: String, into collector: inout LinkCollector) {
            for item in children(of: container) {
                switch kind(item) {
                case "tab": collector.addLink(tab(item, into: &collector))
                case "splitView": for child in children(of: item["id"] as? String ?? "") { collector.addLink(tab(child, into: &collector)) }
                case "list":
                    let group = collector.newGroup(.folder((item["title"] as? String) ?? ""))
                    gather(item, into: group, collector: &collector)
                default: continue
                }
            }
        }

        private func gather(_ folder: [String: Any], into group: Int, collector: inout LinkCollector) {
            for item in children(of: folder["id"] as? String ?? "") {
                switch kind(item) {
                case "tab": collector.add(tab(item, into: &collector), toGroup: group)
                case "splitView", "list": gather(item, into: group, collector: &collector)
                default: continue
                }
            }
        }

        /// A tab's address, with the name the person gave it, or else its page title.
        func tab(_ item: [String: Any], into collector: inout LinkCollector) -> ImportedLink? {
            guard let tab = (item["data"] as? [String: Any])?["tab"] as? [String: Any], let address = tab["savedURL"] as? String else { return nil }
            let name = (item["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return collector.link(address, title: name ?? (tab["savedTitle"] as? String) ?? "")
        }
    }

    /// `{"default": true}` or `{"custom": {"_0": {"directoryBasename": "Profile 1"}}}`.
    private static func profileFolder(_ value: Any?) -> String {
        guard let custom = (value as? [String: Any])?["custom"] as? [String: Any],
              let folder = (custom["_0"] as? [String: Any])?["directoryBasename"] as? String, !folder.isEmpty else { return "Default" }
        return folder
    }

    /// The identifier following `name` in a space's `containerIDs`.
    private static func container(named name: String, in value: Any?) -> String? {
        guard let list = value as? [Any], let index = list.firstIndex(where: { ($0 as? String) == name }), index + 1 < list.count else { return nil }
        return list[index + 1] as? String
    }

    private static func customInfo(_ space: [String: Any]) -> [String: Any] { (space["customInfo"] as? [String: Any]) ?? [:] }

    /// The theme's midtone.
    private static func color(_ space: [String: Any]) -> SpaceColor? {
        guard let tone = (((customInfo(space)["windowTheme"] as? [String: Any])?["primaryColorPalette"] as? [String: Any])?["midTone"]) as? [String: Any],
              let red = tone["red"] as? Double, let green = tone["green"] as? Double, let blue = tone["blue"] as? Double else { return nil }
        func byte(_ value: Double) -> UInt8 { UInt8((min(1, max(0, value)) * 255).rounded()) }
        return SpaceColor(red: byte(red), green: byte(green), blue: byte(blue))
    }

    /// The emoji a space shows instead of its initial.
    private static func emoji(_ space: [String: Any]) -> String? {
        guard let emoji = (customInfo(space)["iconType"] as? [String: Any])?["emoji_v2"] as? String, !emoji.isEmpty else { return nil }
        return emoji
    }
}
