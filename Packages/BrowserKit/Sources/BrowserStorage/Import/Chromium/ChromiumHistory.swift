import BrowserCore
import Foundation

/// A Chromium profile's `History`, read from a copy since the browser keeps it locked.
enum ChromiumHistory {
    /// Seconds between Chromium's epoch (1601-01-01) and 1970-01-01.
    private static let epochOffset: Double = 11_644_473_600

    static func read(_ file: URL, limits: ImportLimits) throws -> ImportedHistory {
        let since = Int64((limits.since.timeIntervalSince1970 + epochOffset) * 1_000_000)
        func date(_ time: Int64) -> Date { Date(timeIntervalSince1970: Double(time) / 1_000_000 - epochOffset) }
        return try SourceFiles.database(file) { database in
            let pages = try database.query("SELECT id, url, title, last_visit_time FROM urls WHERE last_visit_time >= ? ORDER BY last_visit_time DESC", [.integer(since)]) {
                (id: $0.integer(0), address: $0.text(1), title: $0.text(2), last: $0.integer(3))
            }
            let visits = try database.query("""
                SELECT url, visit_time FROM (SELECT url, visit_time, ROW_NUMBER() OVER (PARTITION BY url ORDER BY visit_time DESC) AS rank
                FROM visits WHERE visit_time >= ?) WHERE rank <= ?
                """, [.integer(since), .integer(Int64(limits.visitsPerPage))]) { (page: $0.integer(0), time: $0.integer(1)) }
            let byPage = Dictionary(grouping: visits, by: \.page)
            var history = ImportedHistory()
            for page in pages {
                guard history.pages.count < limits.pages else { break }
                guard let url = URL(string: page.address), NavigationInput.isWebURL(url) else { history.skipped += 1; continue }
                let times = (byPage[page.id] ?? []).map(\.time).sorted(by: >).map(date)
                history.pages.append(ImportedPage(url: url, title: page.title, lastVisit: date(page.last), visits: times.isEmpty ? [date(page.last)] : times))
            }
            return history
        }
    }
}
