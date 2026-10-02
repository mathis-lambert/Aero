import Foundation

/// The sites the New Tab page offers: those of the recent visits, weighed by recency, by how they were
/// reached, and by how close they were to this time of day and kind of day. See docs/BROWSING.md › New Tab.
public enum FrequentSites {
    public struct Site: Equatable, Sendable {
        /// The host without `www.`, with its port: what identifies the site, and what hiding it records.
        public let key: String
        /// The page the site opens: its dominant page, else its home page.
        public let url: URL
        /// The opened page's title; empty for a home page that was never visited.
        public let title: String
    }

    /// Only visits this recent count.
    public static let period: TimeInterval = 28 * 86_400
    private static let halfLife: TimeInterval = 7 * 86_400
    /// A single visit is not a habit.
    private static let minimumVisits = 2
    /// The share of its site's weight from which a page opens instead of the site's home page.
    private static let dominantShare = 0.3
    /// Visits at this time of day weigh up to `1 + hourBoost` times more, fading over `hourSpread` hours.
    private static let hourBoost = 1.5
    private static let hourSpread = 1.5
    /// Visits on the same kind of day, weekday or weekend, weigh this much more.
    private static let dayBoost = 1.25
    private static let typedWeight = 1.5

    public static func key(for url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              var host = url.host(percentEncoded: false)?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("www."), host.count > 4 { host.removeFirst(4) }
        return url.port.map { "\(host):\($0)" } ?? host
    }

    public static func rank(_ visits: some Sequence<SiteVisit>, at now: Date, calendar: Calendar = .current,
                            excluding excluded: Set<String> = [], limit: Int) -> [Site] {
        let hour = Self.hour(of: now, in: calendar)
        let weekend = calendar.isDateInWeekend(now)
        var tallies: [String: Tally] = [:]
        for visit in visits {
            let age = now.timeIntervalSince(visit.date)
            guard visit.transition != .reload, age >= 0, age <= period,
                  let key = key(for: visit.url), !excluded.contains(key) else { continue }
            var distance = abs(Self.hour(of: visit.date, in: calendar) - hour)
            distance = min(distance, 24 - distance)
            let weight = exp2(-age / halfLife)
                * (visit.transition == .typed ? typedWeight : 1)
                * (1 + hourBoost * exp(-(distance / hourSpread) * (distance / hourSpread)))
                * (calendar.isDateInWeekend(visit.date) == weekend ? dayBoost : 1)
            var tally = tallies[key] ?? Tally()
            tally.weight += weight
            tally.visits += 1
            tally.pages[visit.url, default: Page()].weight += weight
            if !visit.title.isEmpty { tally.pages[visit.url]?.title = visit.title }
            tallies[key] = tally
        }
        return tallies
            .filter { $0.value.visits >= minimumVisits }
            .sorted { $0.value.weight != $1.value.weight ? $0.value.weight > $1.value.weight : $0.key < $1.key }
            .prefix(max(0, limit))
            .compactMap { key, tally in
                // Ties go to the shorter address, the likelier landing page.
                guard let (url, page) = tally.pages.max(by: { first, second in
                    first.value.weight != second.value.weight ? first.value.weight < second.value.weight
                        : first.key.absoluteString.count > second.key.absoluteString.count
                }) else { return nil }
                if page.weight >= dominantShare * tally.weight { return Site(key: key, url: url, title: page.title) }
                var home = URLComponents()
                home.scheme = url.scheme
                home.host = url.host(percentEncoded: false)
                home.port = url.port
                home.path = "/"
                return home.url.map { Site(key: key, url: $0, title: "") }
            }
    }

    private struct Page { var weight = 0.0; var title = "" }
    private struct Tally { var weight = 0.0; var visits = 0; var pages: [URL: Page] = [:] }

    private static func hour(of date: Date, in calendar: Calendar) -> Double {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return Double(components.hour ?? 0) + Double(components.minute ?? 0) / 60
    }
}
