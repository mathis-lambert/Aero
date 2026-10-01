import SQLite3
import XCTest

/// What Aero keeps on disk: measuring and cleaning it, resetting Aero, and recovering from damaged records.
/// Schema, migrations, corruption and snapshots are covered by BrowserStoreTests. See docs/STORAGE.md.
@MainActor
final class StorageJourneys: E2ETestCase {
    private var storage: URL { dataRoot.appendingPathComponent("Storage", isDirectory: true) }
    private var primary: URL { storage.appendingPathComponent("Browser.sqlite") }

    private func size(_ item: String) -> String {
        let text = element("storage.size.\(item)")
        return (text.value as? String) ?? text.label
    }

    private func confirm(_ button: String) {
        let action = app.buttons[button == "Restore previous state" ? "storage.confirmRestore" : "storage.confirm"].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: Self.renderTimeout), "\(button) asks first")
        action.click()
    }

    /// Failure modes 1 to 3 and 5 to 8 of Settings › Storage: every item is measured, each action empties what it
    /// says and leaves the rest, and Reset starts Aero fresh, touching only this run's data.
    func testStorageSettingsCleanAndReset() throws {
        try launch { seed in try seed.addSpace("Work") }
        open("favicon.html", expecting: "Favicon fixture")
        open("history-lake.html", expecting: "Alpine Lake fixture")
        openSettings("storage")
        XCTAssertTrue(element("storage.total").waitForExistence(timeout: Self.pageTimeout), "The total is measured")
        for item in ["websiteCache", "history", "icons", "blockingLists", "extensions", "records", "siteData.Personal"] {
            XCTAssertTrue(element("storage.size.\(item)").exists, "\(item) is shown")
        }
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { !self.size("icons").isEmpty && !self.size("icons").contains("Zero") }, "The fixture's icon is on disk")
        attachScreenshot("storage")
        app.buttons["storage.clear.icons"].click()
        XCTAssertTrue(poll(timeout: Self.pageTimeout) { self.size("icons").contains("Zero") }, "Icons are gone and the size follows: \(size("icons"))")
        app.buttons["storage.clear.websiteCache"].click()
        app.buttons["storage.clear.history"].click()
        confirm("Clear history")
        closeSettings()
        app.typeKey("y", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["No history"].waitForExistence(timeout: Self.pageTimeout), "History is empty")
        XCTAssertEqual(Array(labels(of: "sidebar.tab").prefix(2)), ["Favicon fixture", "Alpine Lake"], "Tabs stay")

        openSettings("storage")
        let reset = app.buttons["storage.reset"]
        XCTAssertTrue(reset.waitForExistence(timeout: Self.pageTimeout))
        reveal(reset).click()
        attachScreenshot("reset confirmation")
        confirm("Reset Aero")
        XCTAssertTrue(app.wait(for: .notRunning, timeout: Self.pageTimeout), "Aero quits to reset")
        relaunch()
        XCTAssertEqual(labels(of: "sidebar.space"), ["Main"], "One fresh space")
        XCTAssertTrue(labels(of: "sidebar.tab").isEmpty, "No tabs")
        app.typeKey("y", modifierFlags: .command)
        XCTAssertTrue(app.staticTexts["No history"].waitForExistence(timeout: Self.pageTimeout), "No history")
    }

    /// A damaged database is never replaced by a fresh one: startup stops on recovery, in any language and layout,
    /// keeps the damaged bytes, and restoring brings back the last good launch while archiving them.
    func testDamagedRecordsWaitForRecovery() throws {
        try launch { seed in seed.addTab("solid.html", title: "Solid fixture") }
        quit() // This launch saved its recovery snapshot.
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.appendingPathComponent("Browser.recovery.sqlite").path))
        // A coherent standalone file first: committed WAL pages would otherwise repair the injected damage.
        try checkpoint()
        let damaged = Data("deliberately corrupt E2E database".utf8)
        try damaged.write(to: primary)

        relaunch { $0.french = true; $0.rightToLeft = true; $0.screen = .recovery }
        let restore = app.buttons["storage.restore"], retry = app.buttons["storage.retry"]
        XCTAssertTrue(restore.isHittable && retry.isHittable)
        XCTAssertGreaterThan(retry.frame.midX, app.buttons["storage.showFiles"].frame.midX, "The actions follow the right-to-left direction")
        attachScreenshot("recovery french rtl")
        relaunch { $0.french = false; $0.rightToLeft = false }
        XCTAssertFalse(controlBarInput.exists, "Nothing starts over the damaged records")
        XCTAssertEqual(try Data(contentsOf: primary), damaged, "The damaged file is kept")
        attachScreenshot("recovery")

        app.buttons["storage.restore"].click()
        confirm("Restore previous state")
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: Self.launchTimeout))
        XCTAssertEqual(labels(of: "sidebar.tab"), ["Solid fixture"], "The last good launch is back")
        let archives = try FileManager.default.contentsOfDirectory(at: storage, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("Recovery-") }
        XCTAssertEqual(archives.count, 1)
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(archives.first).appendingPathComponent("Browser.sqlite")), damaged, "…and the damaged file is archived")
    }

    private func checkpoint() throws {
        var db: OpaquePointer?
        defer { sqlite3_close_v2(db) }
        XCTAssertEqual(sqlite3_open_v2(primary.path, &db, SQLITE_OPEN_READWRITE, nil), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(try XCTUnwrap(db), "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, nil), SQLITE_OK)
    }
}
