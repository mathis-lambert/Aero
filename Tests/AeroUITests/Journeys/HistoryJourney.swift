import SQLite3
import XCTest

/// The History page in a tab: recording, a failed write retried, search, opening in place, profile isolation,
/// deletion and clearing. Queries, retention and isolation rules are covered by HistoryStoreTests.
/// See docs/STORAGE.md.
@MainActor
final class HistoryJourney: E2ETestCase {
    private var search: XCUIElement { app.textFields["history.search"] }
    private var rows: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: "history.row") }

    func testHistoryRecordsSearchesAndForgets() throws {
        try launch { seed in try seed.addSpace("Work", profile: "Work") }
        showHistory() // Opens the history database before the fault is injected.
        XCTAssertTrue(app.staticTexts["No history"].waitForExistence(timeout: Self.renderTimeout))
        let database = try openHistory()
        defer { sqlite3_close(database) }
        XCTAssertEqual(sqlite3_exec(database, "CREATE TRIGGER fail_visit BEFORE INSERT ON visits BEGIN SELECT RAISE(ABORT, 'fixture'); END", nil, nil, nil), SQLITE_OK)
        open("history-lake.html", expecting: "Alpine Lake fixture")
        showHistory()
        XCTAssertTrue(app.staticTexts["Some history changes could not be saved. Try the action again."].waitForExistence(timeout: Self.renderTimeout),
                      "A failed write is said")
        XCTAssertEqual(sqlite3_exec(database, "DROP TRIGGER fail_visit", nil, nil, nil), SQLITE_OK)
        quitAndRelaunch()
        tabRows["History"].click()
        XCTAssertTrue(poll { self.labels(of: "history.row") == ["Alpine Lake"] }, "Quitting retried the visit without another navigation")

        open("history-city.html", expecting: "Été à Lyon fixture")
        showHistory()
        XCTAssertEqual(labels(of: "sidebar.tab").filter { $0 == "History" }.count, 1, "⌘Y selects the History tab there is")
        XCTAssertTrue(poll { self.labels(of: "history.row") == ["Été à Lyon", "Alpine Lake"] }, "Newest first, with page titles")
        XCTAssertEqual(app.webViews.count, 0, "The History page is native")
        attachScreenshot("history")
        search.typeText("ete")
        XCTAssertTrue(poll { self.labels(of: "history.row") == ["Été à Lyon"] }, "Search ignores case and diacritics")
        replaceText(of: search, with: "zzzz")
        XCTAssertTrue(app.staticTexts["No results"].waitForExistence(timeout: Self.renderTimeout))
        replaceText(of: search, with: "alpine")
        XCTAssertTrue(poll { self.labels(of: "history.row") == ["Alpine Lake"] })

        space("Work").click()
        open("history-city.html", expecting: "Été à Lyon fixture")
        showHistory()
        XCTAssertTrue(poll { self.labels(of: "history.row") == ["Été à Lyon"] }, "Work has its own history")
        search.typeText("lyon")
        for (name, expected) in [("Main", ["Été à Lyon", "Alpine Lake"]), ("Work", ["Été à Lyon"])] {
            space(name).click()
            XCTAssertEqual(search.value as? String ?? "", "", "\(name) does not inherit another profile's search")
            XCTAssertTrue(poll { self.labels(of: "history.row") == expected }, "\(name) lists its own visits")
        }

        space("Main").click()
        rows.firstMatch.click()
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(poll { self.labels(of: "history.row") == ["Alpine Lake"] }, "Delete removes the selected entry")
        rows.firstMatch.doubleClick()
        XCTAssertTrue(page("Alpine Lake fixture").waitForExistence(timeout: Self.pageTimeout))
        XCTAssertFalse(labels(of: "sidebar.tab").contains("History"), "The entry opens in the History tab itself")
        showHistory()
        app.buttons["history.clear"].click()
        let range = app.popUpButtons["history.clearRange"]
        XCTAssertTrue(range.waitForExistence(timeout: Self.renderTimeout))
        range.click()
        app.menuItems["All history"].click()
        app.buttons["history.confirmClear"].click()
        XCTAssertTrue(app.staticTexts["No history"].waitForExistence(timeout: Self.renderTimeout))
        space("Work").click()
        XCTAssertTrue(poll { self.labels(of: "history.row") == ["Été à Lyon"] }, "Clearing is for the profile only")
    }

    private func showHistory() {
        app.typeKey("y", modifierFlags: .command)
        XCTAssertTrue(search.waitForExistence(timeout: Self.renderTimeout))
    }

    private func openHistory() throws -> OpaquePointer {
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(dataRoot.appendingPathComponent("Storage/History.sqlite").path, &handle), SQLITE_OK)
        return try XCTUnwrap(handle)
    }
}
