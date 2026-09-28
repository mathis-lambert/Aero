import BrowserCore
import Foundation

/// Collects favorites for one space: web addresses only, each once, up to the limit. Adapters keep the source's
/// first-level folders as groups and gather what is nested deeper in them (docs/ONBOARDING.md › Mapping).
struct LinkCollector {
    let limit: Int
    private var space = ImportedSpace()
    private var seen = Set<String>()
    private var count = 0

    init(limit: Int) { self.limit = limit }

    /// `nil` when the address is skipped.
    mutating func link(_ address: String, title: String) -> ImportedLink? {
        guard let url = URL(string: address), NavigationInput.isWebURL(url) else { space.skipped += 1; return nil }
        guard seen.insert(url.absoluteString).inserted else { return nil }
        guard count < limit else { space.skipped += 1; return nil }
        count += 1
        return ImportedLink(url: url, title: title)
    }

    mutating func addTile(_ link: ImportedLink?) { if let link { space.tiles.append(link) } }
    mutating func addLink(_ link: ImportedLink?) { if let link { space.links.append(link) } }

    /// A new group, even when another has the same name: two folders stay two groups.
    mutating func newGroup(_ title: ImportedGroup.Title) -> Int {
        space.groups.append(ImportedGroup(title: title, links: []))
        return space.groups.count - 1
    }

    mutating func add(_ link: ImportedLink?, toGroup index: Int) { if let link { space.groups[index].links.append(link) } }

    /// Empty folders do not become groups.
    func finished() -> ImportedSpace {
        var result = space
        result.groups.removeAll { $0.links.isEmpty }
        return result
    }
}
