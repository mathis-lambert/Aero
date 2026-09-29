import Foundation

/// A Chromium profile's `Favicons`: the icons it already has for the imported favorites, so they arrive with their
/// own icon instead of waiting for their page to load.
enum ChromiumFavicons {
    /// Icons wider than this are larger than the sidebar needs.
    private static let preferredWidth: Int64 = 64
    /// SQLite's default limit on bound parameters is far above this.
    private static let batch = 500

    /// For each page, the icon mapped to that exact address, or else to another page of its site; the bitmap closest
    /// to `preferredWidth` without being smaller when possible.
    static func read(_ file: URL, for pages: [URL]) throws -> [URL: Data] {
        guard !pages.isEmpty else { return [:] }
        return try SourceFiles.database(file) { database in
            var byPage: [String: Int64] = [:], bySite: [String: Int64] = [:]
            for row in try database.query("SELECT page_url, icon_id FROM icon_mapping", row: { (page: $0.text(0), icon: $0.integer(1)) }) {
                byPage[row.page] = row.icon
                if let host = URL(string: row.page)?.host?.lowercased(), bySite[host] == nil { bySite[host] = row.icon }
            }
            var wanted: [URL: Int64] = [:]
            for page in pages {
                if let icon = byPage[page.absoluteString] ?? page.host.flatMap({ bySite[$0.lowercased()] }) { wanted[page] = icon }
            }
            var bitmaps: [Int64: (data: Data, width: Int64)] = [:]
            let icons = Array(Set(wanted.values))
            for start in stride(from: 0, to: icons.count, by: batch) {
                let slice = icons[start..<min(start + batch, icons.count)]
                let marks = Array(repeating: "?", count: slice.count).joined(separator: ",")
                let rows = try database.query("SELECT icon_id, image_data, width FROM favicon_bitmaps WHERE icon_id IN (\(marks))",
                                              slice.map { .integer($0) }) { (icon: $0.integer(0), data: $0.blob(1), width: $0.integer(2)) }
                for row in rows where !row.data.isEmpty {
                    if let current = bitmaps[row.icon], !better(row.width, than: current.width) { continue }
                    bitmaps[row.icon] = (row.data, row.width)
                }
            }
            return wanted.compactMapValues { bitmaps[$0]?.data }
        }
    }

    /// Prefers the smallest bitmap at least `preferredWidth` wide, else the widest.
    private static func better(_ width: Int64, than current: Int64) -> Bool {
        switch (width >= preferredWidth, current >= preferredWidth) {
        case (true, true): width < current
        case (true, false): true
        case (false, true): false
        case (false, false): width > current
        }
    }
}
