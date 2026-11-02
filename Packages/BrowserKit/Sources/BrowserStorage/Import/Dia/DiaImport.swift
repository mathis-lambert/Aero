import Foundation

/// Dia's supported automation snapshot. It exposes favorite tiles, but neither folders nor the distinction
/// between their tabs and open tabs. It also omits the underlying Chromium identity: keep each space isolated.
public enum DiaImport {
    public static func read(_ data: Data, limits: ImportLimits) throws -> [ImportedProfile] {
        guard data.count <= 8 * 1024 * 1024,
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              !snapshot.spaces.isEmpty, snapshot.spaces.count <= 100,
              Set(snapshot.spaces.map(\.index)).count == snapshot.spaces.count,
              snapshot.spaces.allSatisfy({ $0.index > 0 && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { throw BrowserImportError.unreadable }
        let ordered = snapshot.spaces.sorted { $0.index < $1.index }
        // Index suffixes also keep equal or truncated names from accidentally merging identities in Aero.
        let names = ordered.map { String($0.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40)) }
        var usedProfileNames = Set(names)
        return ordered.enumerated().map { position, source in
            var collector = LinkCollector(limit: max(0, limits.links))
            for tab in source.tabs where tab.pinned {
                guard let url = tab.url else { continue }
                let link = collector.link(url, title: tab.title.trimmingCharacters(in: .whitespacesAndNewlines))
                collector.addTile(link)
            }
            var space = collector.finished()
            let base = names[position]
            var name = base
            if names.filter({ $0 == base }).count > 1 {
                var attempt = 0
                repeat {
                    let suffix = attempt == 0 ? " (\(source.index))" : " (\(source.index)-\(attempt))"
                    name = String(base.prefix(40 - suffix.count)) + suffix
                    attempt += 1
                } while usedProfileNames.contains(name)
                usedProfileNames.insert(name)
            }
            space.name = base
            space.position = position
            return ImportedProfile(id: "dia-space:\(source.index)", name: name, spaces: [space], history: ImportedHistory())
        }
    }

    private struct Snapshot: Decodable { let spaces: [Space] }
    private struct Space: Decodable {
        let name: String
        let index: Int
        let tabs: [Tab]
    }
    private struct Tab: Decodable {
        let title: String
        let url: String?
        let pinned: Bool
    }
}
