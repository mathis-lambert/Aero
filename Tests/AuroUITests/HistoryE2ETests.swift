import XCTest

/// The History page in a tab: recording, search, opening, deletion, clearing and persistence.
/// See docs/HISTORY.md.
@MainActor
final class HistoryE2ETests: BrowserE2ETestCase {
    private static let historyTitle = "History"

    private var historyRows: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: "history.row") }
    private var search: XCUIElement { app.textFields["history.search"] }

    func testHistoryTabRecordsSearchesAndOpensVisitsInPlace() {
        open("history-lake.html", expecting: "Alpine Lake fixture")
        open("history-city.html", expecting: "Été à Lyon fixture")
        showHistory()
        XCTAssertEqual(labels(of: "sidebar.tab"), ["Alpine Lake", "Été à Lyon", Self.historyTitle], "History opens as a tab")
        XCTAssertTrue(poll { self.labels(of: "history.row") == ["Été à Lyon", "Alpine Lake"] }, "Newest first, with page titles")
        XCTAssertEqual(app.webViews.count, 0, "The History page is native and creates no web view")
        attachScreenshot("history-tab")

        search.typeText("ete")
        XCTAssertTrue(poll { self.labels(of: "history.row") == ["Été à Lyon"] }, "Search ignores case and diacritics")
        search.typeKey("a", modifierFlags: .command)
        search.typeText("zzzz")
        XCTAssertTrue(app.staticTexts["No results"].waitForExistence(timeout: Self.renderTimeout))

        search.typeKey("a", modifierFlags: .command)
        search.typeText("alpine")
        XCTAssertTrue(poll { self.labels(of: "history.row") == ["Alpine Lake"] })
        historyRows.firstMatch.doubleClick()
        XCTAssertTrue(app.webViews.staticTexts["Alpine Lake fixture"].waitForExistence(timeout: Self.pageTimeout))
        XCTAssertEqual(labels(of: "sidebar.tab"), ["Alpine Lake", "Été à Lyon", "Alpine Lake"], "The entry opens in the History tab itself")
    }

    func testHistoryTabIsReusedPersistsAndCanBeDeletedAndCleared() {
        open("history-lake.html", expecting: "Alpine Lake fixture")
        open("history-city.html", expecting: "Été à Lyon fixture")
        showHistory()
        app.typeKey("t", modifierFlags: .command)
        showHistory()
        XCTAssertEqual(labels(of: "sidebar.tab").filter { $0 == Self.historyTitle }.count, 1, "⌘Y selects the existing History tab")

        relaunch()
        tabRows.matching(NSPredicate(format: "label == %@", Self.historyTitle)).firstMatch.click()
        XCTAssertTrue(poll { self.historyRows.count == 2 }, "The History tab and its entries survive a relaunch")

        historyRows.firstMatch.click()
        app.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(poll { self.labels(of: "history.row") == ["Alpine Lake"] }, "Delete removes the selected entry")

        app.buttons["history.clear"].click()
        let range = app.popUpButtons["history.clearRange"]
        XCTAssertTrue(range.waitForExistence(timeout: Self.renderTimeout))
        range.click()
        app.menuItems["All history"].click()
        app.buttons["history.confirmClear"].click()
        XCTAssertTrue(app.staticTexts["No history"].waitForExistence(timeout: Self.renderTimeout))
        attachScreenshot("history-cleared")
    }

    func testWebsitesCannotOpenInternalPages() {
        open("internal-link.html", expecting: "Open history")
        app.webViews.links["Open history"].click()
        XCTAssertFalse(search.waitForExistence(timeout: 2), "A page cannot navigate to auro://history")
        XCTAssertFalse(labels(of: "sidebar.tab").contains(Self.historyTitle))
    }

    private func showHistory() {
        app.typeKey("y", modifierFlags: .command)
        XCTAssertTrue(search.waitForExistence(timeout: Self.renderTimeout))
    }
}
