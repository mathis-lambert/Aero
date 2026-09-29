import BrowserCore
import Foundation
import Testing
@testable import BrowserStorage

// docs/ONBOARDING.md › Failure modes 3, 6 and 9: source formats, their limits and damaged files, which UI tests
// cannot vary exhaustively. Written before the readers.

private let day: TimeInterval = 24 * 60 * 60
private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
private let limits = ImportLimits(since: now.addingTimeInterval(-365 * day), links: 10_000, pages: 100_000, visitsPerPage: 20)

private final class Folder {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("aero-import-\(UUID().uuidString)", isDirectory: true)
    init() { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: url) }
    func file(_ path: String, _ data: Data) throws -> URL {
        let file = url.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file)
        return file
    }
}

private func json(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
private func links(_ list: [ImportedLink]) -> [String] { list.map(\.url.absoluteString) }

// MARK: - Arc

/// Arc's sidebar interleaves identifiers and records in its arrays, as the real file does.
private func arcSidebar(spaces: [[String: Any]], items: [[String: Any]], topApps: [Any] = []) -> [String: Any] {
    ["version": 1, "sidebar": ["containers": [["global": [:]], [
        "spaces": spaces.flatMap { [$0["id"] as Any, $0] },
        "items": items.flatMap { [$0["id"] as Any, $0] },
        "topAppsContainerIDs": topApps
    ]]]]
}

private func arcSpace(_ id: String, _ title: String, pinned: String, unpinned: String, profile: [String: Any] = ["default": true],
                      midTone: (Double, Double, Double) = (0.3, 0.45, 0.35), emoji: String? = nil) -> [String: Any] {
    var customInfo: [String: Any] = ["windowTheme": ["primaryColorPalette": ["midTone": ["red": midTone.0, "green": midTone.1, "blue": midTone.2, "alpha": 1, "colorSpace": "sRGB"]]]]
    if let emoji { customInfo["iconType"] = ["emoji_v2": emoji, "emoji": 128_187] }
    return ["id": id, "title": title, "profile": profile, "containerIDs": ["unpinned", unpinned, "pinned", pinned], "customInfo": customInfo]
}

private func arcContainer(_ id: String, children: [String]) -> [String: Any] {
    ["id": id, "childrenIds": children, "data": ["itemContainer": ["containerType": [:]]]]
}
private func arcFolder(_ id: String, _ title: String, parent: String, children: [String]) -> [String: Any] {
    ["id": id, "title": title, "parentID": parent, "childrenIds": children, "data": ["list": [:]]]
}
private func arcTab(_ id: String, _ url: String, _ title: String, parent: String, name: String? = nil) -> [String: Any] {
    var item: [String: Any] = ["id": id, "parentID": parent, "childrenIds": [], "data": ["tab": ["savedURL": url, "savedTitle": title]]]
    if let name { item["title"] = name }
    return item
}

@Test func arcSpacesKeepTheirProfilePinnedFavoritesFoldersAndColor() throws {
    let data = try json(arcSidebar(
        spaces: [
            arcSpace("s1", "Personal", pinned: "p1", unpinned: "u1", midTone: (0.2, 0.6, 0.3)),
            arcSpace("s2", "Work", pinned: "p2", unpinned: "u2", profile: ["custom": ["_0": ["directoryBasename": "Profile 1", "name": "Work"]]], emoji: "💻")
        ],
        items: [
            arcContainer("p1", children: ["t1", "f1"]), arcContainer("u1", children: ["t9"]),
            arcTab("t1", "https://mail.example.com/", "Mail", parent: "p1", name: "Inbox"),
            arcFolder("f1", "Reading", parent: "p1", children: ["t2", "f2", "t5"]),
            arcTab("t2", "https://news.example.com/", "News", parent: "f1"),
            arcFolder("f2", "Long reads", parent: "f1", children: ["t3"]),
            arcTab("t3", "https://essays.example.com/", "Essays", parent: "f2"),
            arcTab("t5", "https://podcast.example.com/", "Podcast", parent: "f1"),
            arcTab("t9", "https://open.example.com/", "Open tab", parent: "u1"),
            arcContainer("p2", children: ["t4"]), arcContainer("u2", children: []),
            arcTab("t4", "https://work.example.com/", "Work", parent: "p2")
        ]))
    let sidebar = try ArcSidebar.read(data, limits: limits)
    #expect(sidebar.spaces.map(\.space.name) == ["Personal", "Work"])
    #expect(sidebar.spaces.map(\.profileFolder) == ["Default", "Profile 1"])
    let personal = sidebar.spaces[0].space
    // A named pinned tab keeps its name as the favorite's title.
    #expect(personal.links == [ImportedLink(url: URL(string: "https://mail.example.com/")!, title: "Inbox")])
    // A first-level folder is a group; what is nested in it is gathered in it, in order.
    #expect(personal.groups.map(\.title) == [.folder("Reading")])
    #expect(links(personal.groups[0].links) == ["https://news.example.com/", "https://essays.example.com/", "https://podcast.example.com/"])
    // The theme's midtone becomes the space color; the space's emoji comes along.
    #expect(personal.color == SpaceColor(red: 51, green: 153, blue: 77))
    #expect(personal.emoji == nil)
    #expect(sidebar.spaces[1].space.emoji == "💻")
    // Unpinned tabs are open tabs: never imported.
    #expect(!sidebar.spaces.flatMap { links($0.space.links) + $0.space.groups.flatMap { links($0.links) } }.contains("https://open.example.com/"))
}

@Test func arcSkipsNonTabItemsAndNonWebAddressesButKeepsSplitViewTabs() throws {
    let data = try json(arcSidebar(
        spaces: [arcSpace("s1", "Personal", pinned: "p1", unpinned: "u1")],
        items: [
            arcContainer("p1", children: ["doc", "welcome", "split", "file", "easel"]), arcContainer("u1", children: []),
            ["id": "doc", "parentID": "p1", "childrenIds": [], "data": ["arcDocument": ["arcDocumentID": "x"]]],
            ["id": "welcome", "parentID": "p1", "childrenIds": [], "data": ["welcomeToArc": [:]]],
            ["id": "split", "parentID": "p1", "childrenIds": ["a", "b"], "data": ["splitView": [:]]],
            arcTab("a", "https://left.example.com/", "Left", parent: "split"),
            arcTab("b", "https://right.example.com/", "Right", parent: "split"),
            arcTab("file", "file:///Users/someone/notes.txt", "Notes", parent: "p1"),
            arcTab("easel", "arc://easel/123", "Easel", parent: "p1")
        ]))
    let space = try ArcSidebar.read(data, limits: limits).spaces[0].space
    #expect(links(space.links) == ["https://left.example.com/", "https://right.example.com/"])
    #expect(space.groups.isEmpty)
    #expect(space.skipped == 2)
}

@Test func arcTopAppsBecomeTilesOfEverySpaceOfTheirProfile() throws {
    let data = try json(arcSidebar(
        spaces: [arcSpace("s1", "Personal", pinned: "p1", unpinned: "u1"), arcSpace("s2", "Side", pinned: "p2", unpinned: "u2")],
        items: [
            arcContainer("p1", children: []), arcContainer("u1", children: []), arcContainer("p2", children: []), arcContainer("u2", children: []),
            arcContainer("top", children: ["g"]), arcTab("g", "https://calendar.example.com/", "Calendar", parent: "top")
        ],
        topApps: [["default": true], "top"]))
    let sidebar = try ArcSidebar.read(data, limits: limits)
    // Arc shows a profile's favorites above every one of its spaces; Aero keeps favorites per space.
    #expect(links(sidebar.spaces[0].space.tiles) == ["https://calendar.example.com/"])
    #expect(links(sidebar.spaces[1].space.tiles) == ["https://calendar.example.com/"])
}

@Test func arcSidebarThatIsNotArcsFormatIsUnreadable() throws {
    for data in [Data(), Data("{".utf8), try json(["sidebar": ["containers": []]]), try json(["version": 1])] {
        #expect(throws: BrowserImportError.unreadable) { try ArcSidebar.read(data, limits: limits) }
    }
}

// MARK: - Chromium bookmarks

private func chromiumURL(_ url: String, _ name: String) -> [String: Any] { ["type": "url", "url": url, "name": name] }
private func chromiumFolder(_ name: String, _ children: [[String: Any]]) -> [String: Any] { ["type": "folder", "name": name, "children": children] }
private func chromiumBookmarks(bar: [[String: Any]], other: [[String: Any]] = [], synced: [[String: Any]] = []) -> [String: Any] {
    ["version": 1, "roots": [
        "bookmark_bar": chromiumFolder("Bookmarks bar", bar),
        "other": chromiumFolder("Other bookmarks", other),
        "synced": chromiumFolder("Mobile bookmarks", synced)
    ]]
}

@Test func chromiumBarBecomesFavoritesFoldersBecomeGroupsAndOtherBookmarksOneGroup() throws {
    let data = try json(chromiumBookmarks(
        bar: [
            chromiumURL("https://a.example.com/", "A"),
            chromiumFolder("Work", [chromiumURL("https://w.example.com/", "W"), chromiumFolder("Clients", [chromiumURL("https://c.example.com/", "C")])]),
            chromiumURL("javascript:alert(1)", "Bookmarklet"),
            chromiumURL("chrome://settings", "Settings"),
            chromiumURL("https://a.example.com/", "A again")
        ],
        other: [chromiumURL("https://o.example.com/", "O"), chromiumFolder("Recipes", [chromiumURL("https://r.example.com/", "R")])],
        synced: [chromiumURL("https://m.example.com/", "M")]))
    let space = try ChromiumBookmarks.read(data, limits: limits)
    #expect(space.links == [ImportedLink(url: URL(string: "https://a.example.com/")!, title: "A")])
    // Each first-level folder of the bar is a group gathering its subfolders; other and mobile bookmarks are a group each.
    #expect(space.groups.map(\.title) == [.folder("Work"), .otherBookmarks, .mobileBookmarks])
    #expect(links(space.groups[0].links) == ["https://w.example.com/", "https://c.example.com/"])
    #expect(links(space.groups[1].links) == ["https://o.example.com/", "https://r.example.com/"])
    #expect(links(space.groups[2].links) == ["https://m.example.com/"])
    // Two non-web addresses; the repeated address is not an error, it is kept once.
    #expect(space.skipped == 2)
    #expect(space.tiles.isEmpty)
}

@Test func chromiumBookmarksStopAtTheLinkLimitAndSkipEmptyFolders() throws {
    let many = (0..<25).map { chromiumURL("https://example.com/\($0)", "\($0)") }
    let data = try json(chromiumBookmarks(bar: [chromiumFolder("Empty", [])] + many))
    let space = try ChromiumBookmarks.read(data, limits: ImportLimits(since: limits.since, links: 10, pages: 10, visitsPerPage: 1))
    #expect(space.links.count == 10)
    #expect(space.skipped == 15)
    #expect(space.groups.isEmpty)
}

@Test func chromiumBookmarksSurviveDeepNestingAndRejectDamagedFiles() throws {
    var folder = chromiumFolder("Leaf", [chromiumURL("https://deep.example.com/", "Deep")])
    for level in 0..<200 { folder = chromiumFolder("L\(level)", [folder]) }
    let deep = try ChromiumBookmarks.read(try json(chromiumBookmarks(bar: [folder])), limits: limits)
    #expect(links(deep.groups.flatMap(\.links)) == ["https://deep.example.com/"])
    for data in [Data(), Data("[]".utf8), try json(["roots": 3])] {
        #expect(throws: BrowserImportError.unreadable) { try ChromiumBookmarks.read(data, limits: limits) }
    }
}

// MARK: - Chromium history

/// Microseconds since 1601-01-01, Chromium's clock.
private func chromiumTime(_ date: Date) -> Int64 { Int64((date.timeIntervalSince1970 + 11_644_473_600) * 1_000_000) }

private func chromiumHistory(in folder: Folder, _ pages: [(url: String, title: String, visits: [Date])]) throws -> URL {
    let file = folder.url.appendingPathComponent("History")
    let database = try SQLiteDatabase(file: file)
    try database.execute("CREATE TABLE urls (id INTEGER PRIMARY KEY, url TEXT, title TEXT, visit_count INTEGER, last_visit_time INTEGER)")
    try database.execute("CREATE TABLE visits (id INTEGER PRIMARY KEY, url INTEGER, visit_time INTEGER)")
    for (index, page) in pages.enumerated() {
        try database.run("INSERT INTO urls VALUES (?, ?, ?, ?, ?)", [.integer(Int64(index + 1)), .text(page.url), .text(page.title),
                                                                      .integer(Int64(page.visits.count)), .integer(chromiumTime(page.visits.max() ?? now))])
        for visit in page.visits { try database.run("INSERT INTO visits (url, visit_time) VALUES (?, ?)", [.integer(Int64(index + 1)), .integer(chromiumTime(visit))]) }
    }
    return file
}

@Test func chromiumHistoryKeepsRecentWebPagesNewestFirstWithBoundedVisits() throws {
    let folder = Folder()
    let file = try chromiumHistory(in: folder, [
        ("https://old.example.com/", "Old", [now.addingTimeInterval(-400 * day)]),
        ("https://recent.example.com/", "Recent", (0..<30).map { now.addingTimeInterval(-Double($0) * 3600) }),
        ("https://older.example.com/", "Older", [now.addingTimeInterval(-10 * day)]),
        ("chrome://history", "History", [now]),
        ("file:///tmp/x.html", "Local", [now])
    ])
    let history = try ChromiumHistory.read(file, limits: limits)
    #expect(history.pages.map(\.url.absoluteString) == ["https://recent.example.com/", "https://older.example.com/"])
    let recent = history.pages[0]
    #expect(recent.title == "Recent")
    #expect(recent.visits.count == 20)
    #expect(recent.visits == recent.visits.sorted(by: >))
    #expect(abs(recent.lastVisit.timeIntervalSince(now)) < 0.001)
    #expect(history.skipped == 2)
}

@Test func chromiumHistoryStopsAtThePageLimit() throws {
    let folder = Folder()
    let file = try chromiumHistory(in: folder, (0..<40).map { ("https://example.com/\($0)", "\($0)", [now.addingTimeInterval(-Double($0) * 60)]) })
    let history = try ChromiumHistory.read(file, limits: ImportLimits(since: limits.since, links: 10, pages: 25, visitsPerPage: 3))
    #expect(history.pages.count == 25)
    #expect(history.pages.first?.url.absoluteString == "https://example.com/0")
}

@Test func damagedHistoryIsUnreadable() throws {
    let folder = Folder()
    let garbage = try folder.file("History", Data("not a database".utf8))
    #expect(throws: BrowserImportError.unreadable) { try ChromiumHistory.read(garbage, limits: limits) }
    #expect(throws: BrowserImportError.unreadable) { try ChromiumHistory.read(folder.url.appendingPathComponent("Missing"), limits: limits) }
}

// MARK: - Safari

private func safariLeaf(_ url: String, _ title: String) -> [String: Any] {
    ["WebBookmarkType": "WebBookmarkTypeLeaf", "URLString": url, "URIDictionary": ["title": title]]
}
private func safariList(_ title: String, _ children: [[String: Any]]) -> [String: Any] {
    ["WebBookmarkType": "WebBookmarkTypeList", "Title": title, "Children": children]
}

@Test func safariFavoritesBarBecomesFavoritesMenuFoldersGroupsAndReadingListIsSkipped() throws {
    let root = safariList("", [
        ["WebBookmarkType": "WebBookmarkTypeProxy", "Title": "History"],
        safariList("BookmarksBar", [safariLeaf("https://bar.example.com/", "Bar"), safariList("Travel", [safariLeaf("https://t.example.com/", "T")])]),
        safariList("BookmarksMenu", [safariLeaf("https://menu.example.com/", "Menu"), safariList("Cooking", [safariLeaf("https://k.example.com/", "K")])]),
        safariList("com.apple.ReadingList", [safariLeaf("https://later.example.com/", "Later")]),
        safariList("Archive", [safariLeaf("https://a.example.com/", "A"), safariLeaf("feed://x.example.com/", "Feed")])
    ])
    let data = try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
    let space = try SafariBookmarks.read(data, limits: limits)
    #expect(links(space.links) == ["https://bar.example.com/"])
    // A bar folder is a group; the Bookmarks menu is one group gathering its folders; other top-level folders are groups.
    #expect(space.groups.map(\.title) == [.folder("Travel"), .bookmarksMenu, .folder("Archive")])
    #expect(links(space.groups[1].links) == ["https://menu.example.com/", "https://k.example.com/"])
    #expect(!links(space.groups.flatMap(\.links)).contains("https://later.example.com/"))
    #expect(space.skipped == 1)
    #expect(throws: BrowserImportError.unreadable) { try SafariBookmarks.read(Data("nope".utf8), limits: limits) }
}

@Test func safariHistoryUsesReferenceDatesAndTheLatestVisitsTitle() throws {
    let folder = Folder()
    let file = folder.url.appendingPathComponent("History.db")
    let database = try SQLiteDatabase(file: file)
    try database.execute("CREATE TABLE history_items (id INTEGER PRIMARY KEY, url TEXT, visit_count INTEGER)")
    try database.execute("CREATE TABLE history_visits (id INTEGER PRIMARY KEY, history_item INTEGER, visit_time REAL, title TEXT)")
    try database.run("INSERT INTO history_items VALUES (1, 'https://s.example.com/', 2)")
    try database.run("INSERT INTO history_visits (history_item, visit_time, title) VALUES (1, ?, 'Before'), (1, ?, 'After')",
                     [.real(now.addingTimeInterval(-day).timeIntervalSinceReferenceDate), .real(now.timeIntervalSinceReferenceDate)])
    try database.run("INSERT INTO history_items VALUES (2, 'https://ancient.example.com/', 1)")
    try database.run("INSERT INTO history_visits (history_item, visit_time, title) VALUES (2, ?, 'Ancient')", [.real(now.addingTimeInterval(-500 * day).timeIntervalSinceReferenceDate)])
    let history = try SafariHistory.read(file, limits: limits)
    #expect(history.pages.map(\.title) == ["After"])
    #expect(history.pages[0].visits.count == 2)
    #expect(abs(history.pages[0].lastVisit.timeIntervalSince(now)) < 0.001)
}

// MARK: - Sources

@Test func sourcesListInstalledBrowsersWithTheirProfilesWithoutReadingData() throws {
    let support = Folder(), safari = Folder()
    _ = try support.file("Arc/StorableSidebar.json", Data("{}".utf8))
    _ = try support.file("Arc/User Data/Default/History", Data())
    _ = try support.file("Google/Chrome/Profile 1/Bookmarks", Data("{}".utf8))
    _ = try support.file("Google/Chrome/Local State", try json(["profile": ["info_cache": ["Profile 1": ["name": "Mathis"]]]]))
    try FileManager.default.createDirectory(at: support.url.appendingPathComponent("BraveSoftware/Brave-Browser/Crashpad"), withIntermediateDirectories: true)
    _ = try safari.file("Bookmarks.plist", try PropertyListSerialization.data(fromPropertyList: safariList("", []), format: .binary, options: 0))
    let sources = BrowserImport.sources(applicationSupport: support.url, safari: safari.url)
    // In the order of ChromiumBrowser.all, then Safari.
    #expect(sources.map(\.name) == ["Google Chrome", "Arc", "Safari"])
    #expect(sources.map(\.favorites) == [.bookmarks, .spaces, .bookmarks])
    #expect(sources[0].profiles.map(\.name) == ["Mathis"])
    #expect(sources[1].profiles.map(\.folder.lastPathComponent) == ["Default"])
    #expect(sources.allSatisfy { $0.isReadable })
    // Without Safari's folder, Safari is not offered.
    #expect(!BrowserImport.sources(applicationSupport: support.url, safari: support.url.appendingPathComponent("None")).contains { $0.name == "Safari" })
}

@Test func readingASourceGroupsSpacesAndHistoryByProfile() throws {
    let support = Folder()
    _ = try support.file("Arc/StorableSidebar.json", try json(arcSidebar(
        spaces: [arcSpace("s1", "Personal", pinned: "p1", unpinned: "u1"),
                 arcSpace("s2", "Work", pinned: "p2", unpinned: "u2", profile: ["custom": ["_0": ["directoryBasename": "Profile 1"]]]),
                 arcSpace("s3", "Studio", pinned: "p3", unpinned: "u3")],
        items: ["p1", "u1", "p2", "u2", "p3", "u3"].map { arcContainer($0, children: []) })))
    _ = try support.file("Arc/User Data/Local State", try json(["profile": ["info_cache": ["Default": ["name": "Me"], "Profile 1": ["name": "Job"]]]]))
    let historyFolder = Folder()
    let history = try chromiumHistory(in: historyFolder, [("https://p.example.com/", "P", [now])])
    try FileManager.default.createDirectory(at: support.url.appendingPathComponent("Arc/User Data/Default"), withIntermediateDirectories: true)
    try FileManager.default.copyItem(at: history, to: support.url.appendingPathComponent("Arc/User Data/Default/History"))
    let source = try #require(BrowserImport.sources(applicationSupport: support.url, safari: support.url.appendingPathComponent("None")).first)
    let profiles = try BrowserImport.read(source, limits: limits)
    #expect(profiles.map(\.name) == ["Me", "Job"])
    #expect(profiles[0].spaces.map(\.name) == ["Personal", "Studio"])
    #expect(profiles[1].spaces.map(\.name) == ["Work"])
    #expect(profiles[0].history.pages.map(\.url.absoluteString) == ["https://p.example.com/"])
    #expect(profiles[1].history.pages.isEmpty)
}

// MARK: - Dia

@Test func diaGivesOneSpacePerProfileWithItsNameColorAndHistoryButNoFavorites() throws {
    let support = Folder()
    // Dia's live spaces are in an encrypted tabs.db, which is never read.
    _ = try support.file("Dia/User Data/Profile 1/tabs.db", Data([0xB0, 0xF7, 0x1E, 0x0F]))
    _ = try support.file("Dia/User Data/Profile 1/Bookmarks", try json(chromiumBookmarks(bar: [chromiumURL("https://a.example.com/", "A")])))
    _ = try support.file("Dia/User Data/Profile 2/History", Data())
    _ = try support.file("Dia/User Data/Local State", try json(["profile": ["info_cache": [
        "Profile 1": ["name": "Perso", "profile_highlight_color": -12_345_678],
        "Profile 2": ["name": "Boulot"]
    ]]]))
    let source = try #require(BrowserImport.sources(applicationSupport: support.url, safari: support.url.appendingPathComponent("None")).first)
    #expect(source.favorites == .unreadable)
    let profiles = try BrowserImport.read(source, limits: limits)
    #expect(profiles.map(\.name) == ["Perso", "Boulot"])
    #expect(profiles.map { $0.spaces.map(\.name) } == [["Perso"], ["Boulot"]])
    // Dia shows its encrypted favorites, not what is left in its Bookmarks file.
    #expect(profiles.allSatisfy { $0.spaces.allSatisfy(\.allLinks.isEmpty) })
    // The profile's highlight color (ARGB) becomes its space's color; without one, the app picks.
    let argb = UInt32(bitPattern: -12_345_678)
    #expect(profiles[0].spaces[0].color == SpaceColor(red: UInt8((argb >> 16) & 0xFF), green: UInt8((argb >> 8) & 0xFF), blue: UInt8(argb & 0xFF)))
    #expect(profiles[1].spaces[0].color == nil)
    #expect(profiles[1].spaces[0].links.isEmpty)
}

// MARK: - Icons

/// The tables of a Chromium `Favicons` database that the reader uses.
private func chromiumFavicons(in folder: Folder, mappings: [(page: String, icon: Int64)], bitmaps: [(icon: Int64, width: Int64, bytes: UInt8)]) throws -> URL {
    let file = folder.url.appendingPathComponent("Favicons")
    let database = try SQLiteDatabase(file: file)
    try database.execute("CREATE TABLE icon_mapping (id INTEGER PRIMARY KEY, page_url TEXT, icon_id INTEGER)")
    try database.execute("CREATE TABLE favicon_bitmaps (id INTEGER PRIMARY KEY, icon_id INTEGER, image_data BLOB, width INTEGER, height INTEGER)")
    for mapping in mappings { try database.run("INSERT INTO icon_mapping (page_url, icon_id) VALUES (?, ?)", [.text(mapping.page), .integer(mapping.icon)]) }
    for bitmap in bitmaps {
        // One byte stands for the image; the reader never decodes it.
        try database.run("INSERT INTO favicon_bitmaps (icon_id, image_data, width, height) VALUES (?, X'\(String(format: "%02X", bitmap.bytes))', ?, ?)",
                         [.integer(bitmap.icon), .integer(bitmap.width), .integer(bitmap.width)])
    }
    return file
}

@Test func faviconsComeFromTheExactPageOrElseItsSiteAtTheSidebarsSize() throws {
    let folder = Folder()
    let file = try chromiumFavicons(in: folder,
        mappings: [("https://mail.example.com/inbox", 1), ("https://news.example.com/", 2), ("https://news.example.com/world", 3)],
        bitmaps: [(1, 16, 0x10), (1, 64, 0x40), (1, 256, 0xFF), (2, 32, 0x20), (3, 16, 0x03)])
    let mail = URL(string: "https://mail.example.com/inbox")!, sport = URL(string: "https://news.example.com/sport")!
    let unknown = URL(string: "https://unknown.example.com/")!
    let icons = try ChromiumFavicons.read(file, for: [mail, sport, unknown])
    // The smallest bitmap at least 64 pixels wide; a page Chromium never mapped takes its site's icon.
    #expect(icons[mail] == Data([0x40]))
    #expect(icons[sport] != nil)
    #expect(icons[unknown] == nil)
    #expect(throws: BrowserImportError.unreadable) { try ChromiumFavicons.read(folder.url.appendingPathComponent("Missing"), for: [mail]) }
}
