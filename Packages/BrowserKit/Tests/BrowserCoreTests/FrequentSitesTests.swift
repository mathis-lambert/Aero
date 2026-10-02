import BrowserCore
import Foundation
import Testing

// docs/BROWSING.md › New Tab. Written as failure modes first:
// 1. A site splits in two over `www.`, or merges with another port or a non-web address.
// 2. A one-off visit, a reload, an old or future visit, or a hidden site is offered.
// 3. A frequent but stale site outranks one used today, or typing an address counts like a passing link.
// 4. The time of day does not lift the sites of this hour, or wraps wrongly around midnight.
// 5. A site opens a page visited once instead of its dominant page, or a random article instead of its home page.
// 6. Equal weights come out in a different order from one call to the next.

private let hour: TimeInterval = 3600
private let day = 24 * hour

private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}

/// A Wednesday at 9:00 in Paris.
private let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 9))!

private func visit(_ address: String, _ age: TimeInterval, _ transition: HistoryTransition = .link, title: String = "") -> SiteVisit {
    SiteVisit(url: URL(string: address)!, title: title, date: now - age, transition: transition)
}

private func rank(_ visits: [SiteVisit], excluding excluded: Set<String> = [], limit: Int = 8) -> [String] {
    FrequentSites.rank(visits, at: now, calendar: calendar, excluding: excluded, limit: limit).map(\.key)
}

@Test func sitesAreHostsWithoutWWW() {
    #expect(FrequentSites.key(for: URL(string: "https://WWW.Example.com/a")!) == "example.com")
    #expect(FrequentSites.key(for: URL(string: "http://localhost:8080/")!) == "localhost:8080")
    #expect(FrequentSites.key(for: URL(string: "https://www./")!) == "www.")
    #expect(FrequentSites.key(for: URL(string: "aero://history")!) == nil)
    #expect(FrequentSites.key(for: URL(string: "file:///tmp/a.html")!) == nil)
    #expect(rank([visit("https://www.example.com/", hour), visit("https://example.com/", 2 * hour)]) == ["example.com"])
    #expect(rank([visit("http://localhost:1/", hour), visit("http://localhost:2/", hour)]).isEmpty, "Each port is its own site")
}

@Test func onlyRepeatedRecentVisiblePagesCount() {
    let base = [visit("https://kept.example/", hour), visit("https://kept.example/", 2 * hour)]
    #expect(rank(base + [visit("https://once.example/", hour)]) == ["kept.example"])
    #expect(rank(base + [visit("https://reloaded.example/", hour), visit("https://reloaded.example/", hour, .reload)]) == ["kept.example"])
    #expect(rank(base + [visit("https://old.example/", 29 * day), visit("https://old.example/", 30 * day)]) == ["kept.example"])
    #expect(rank(base + [visit("https://future.example/", -hour), visit("https://future.example/", -2 * hour)]) == ["kept.example"])
    #expect(rank(base, excluding: ["kept.example"]).isEmpty)
    #expect(rank(base, limit: 0).isEmpty)
}

@Test func recentAndTypedVisitsWeighMore() {
    let stale = (0..<4).map { _ in visit("https://stale.example/", 21 * day) }
    let fresh = (0..<2).map { _ in visit("https://fresh.example/", day) }
    #expect(rank(stale + fresh) == ["fresh.example", "stale.example"])
    let linked = (0..<4).map { _ in visit("https://linked.example/", day) }
    let typed = (0..<2).map { _ in visit("https://typed.example/", day, .typed) }
    #expect(rank(linked + typed) == ["linked.example", "typed.example"], "Four links still outweigh two typed visits")
    #expect(rank(linked.prefix(2) + typed) == ["typed.example", "linked.example"])
}

@Test func theTimeOfDayLiftsItsSites() {
    // Yesterday at 9:00 against yesterday at 15:00: the same age, the same kind of day.
    let morning = (0..<2).map { _ in visit("https://morning.example/", day) }
    let afternoon = (0..<2).map { _ in visit("https://afternoon.example/", day - 6 * hour) }
    #expect(rank(afternoon + morning) == ["morning.example", "afternoon.example"])
    // At 0:30, a visit at 23:30 is an hour away, not 23.
    let late = calendar.date(from: DateComponents(year: 2026, month: 9, day: 30, hour: 0, minute: 30))!
    let night = (0..<2).map { _ in SiteVisit(url: URL(string: "https://night.example/")!, title: "", date: late - hour, transition: .link) }
    let noon = (0..<2).map { _ in SiteVisit(url: URL(string: "https://noon.example/")!, title: "", date: late - 12.5 * hour, transition: .link) }
    #expect(FrequentSites.rank(noon + night, at: late, calendar: calendar, limit: 8).map(\.key) == ["night.example", "noon.example"])
    // Saturday 9:00 against Tuesday 9:00, seen on a Wednesday.
    let weekend = (0..<2).map { _ in visit("https://weekend.example/", 4 * day) }
    let weekday = (0..<2).map { _ in visit("https://weekday.example/", day) }
    #expect(rank(weekend + weekday).first == "weekday.example")
}

@Test func aSiteOpensItsDominantPageOrItsHome() {
    let inbox = (0..<5).map { _ in visit("https://mail.example/inbox", hour, title: "Inbox") }
    let message = visit("https://mail.example/message/1", hour, title: "A message")
    let mail = FrequentSites.rank(inbox + [message], at: now, calendar: calendar, limit: 8)
    #expect(mail.map(\.url.absoluteString) == ["https://mail.example/inbox"])
    #expect(mail.map(\.title) == ["Inbox"])
    let articles = (1...5).map { visit("https://news.example/article/\($0)", hour, title: "Article \($0)") }
    let news = FrequentSites.rank(articles, at: now, calendar: calendar, limit: 8)
    #expect(news.map(\.url.absoluteString) == ["https://news.example/"])
    #expect(news.map(\.title) == [""])
    let port = FrequentSites.rank((1...4).map { visit("http://localhost:8080/\($0)", hour) }, at: now, calendar: calendar, limit: 8)
    #expect(port.map(\.url.absoluteString) == ["http://localhost:8080/"])
}

@Test func equalWeightsKeepOneOrder() {
    let visits = ["b", "c", "a"].flatMap { name in (0..<2).map { _ in visit("https://\(name).example/", hour) } }
    for _ in 0..<5 { #expect(rank(visits.shuffled()) == ["a.example", "b.example", "c.example"]) }
    let pages = [visit("https://site.example/long/path", hour), visit("https://site.example/", hour)]
    #expect(FrequentSites.rank(pages, at: now, calendar: calendar, limit: 1).map(\.url.absoluteString) == ["https://site.example/"])
}
