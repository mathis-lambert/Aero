import SQLite3
import XCTest

/// Actual startup failures and recovery UI, against disposable data owned by the test runner.
@MainActor
final class StorageE2ETests: BrowserE2ETestCase {
    private var storage = URL.temporaryDirectory

    override func setUp() async throws {
        try await super.setUp()
        let path = try XCTUnwrap(app.launchEnvironment[TestApplication.testDataKey])
        storage = URL(fileURLWithPath: path, isDirectory: true).appendingPathComponent("Storage")
    }

    func testCorruptPrimaryIsPreservedAndExplicitRecoveryRestoresTabs() throws {
        try seedRecovery()
        let corrupt = Data("deliberately corrupt E2E database".utf8)
        try corrupt.write(to: primary)
        app.launch()
        XCTAssertTrue(app.buttons["storage.retry"].waitForExistence(timeout: TestApplication.launchTimeout))
        XCTAssertFalse(controlBarInput.exists)
        XCTAssertEqual(try Data(contentsOf: primary), corrupt)
        attachScreenshot("storage-corrupt-preserved")

        restore()
        XCTAssertEqual(labels(of: "sidebar.tab"), ["Solid fixture"])
        let archives = try FileManager.default.contentsOfDirectory(at: storage, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("Recovery-") }
        XCTAssertEqual(archives.count, 1)
        let archive = try XCTUnwrap(archives.first)
        XCTAssertEqual(try Data(contentsOf: archive.appendingPathComponent("Browser.sqlite")), corrupt)
        attachScreenshot("storage-restored")
    }

    func testMissingPrimaryRequiresRecoveryInsteadOfFreshState() throws {
        try seedRecovery()
        try FileManager.default.removeItem(at: primary)
        app.launch()
        XCTAssertTrue(app.buttons["storage.retry"].waitForExistence(timeout: TestApplication.launchTimeout))
        XCTAssertFalse(FileManager.default.fileExists(atPath: primary.path))
        restore()
        XCTAssertEqual(labels(of: "sidebar.tab"), ["Solid fixture"])
    }

    func testNewerSchemaIsPreservedAndCannotBeRestoredOver() throws {
        try seedRecovery()
        try setFutureVersion()
        let original = try Data(contentsOf: primary)
        app.launch()
        XCTAssertTrue(app.buttons["storage.retry"].waitForExistence(timeout: TestApplication.launchTimeout))
        XCTAssertTrue(app.staticTexts["This data requires a newer version of Aero. Your files have been kept unchanged."].exists)
        XCTAssertFalse(app.buttons["storage.restore"].exists)
        app.buttons["storage.retry"].click()
        XCTAssertEqual(try Data(contentsOf: primary), original)
        attachScreenshot("storage-newer-format-refused")
    }

    func testRecoveryActionsWithFrenchLabelsAndRightToLeftLayout() throws {
        try seedRecovery()
        try Data("corrupt layout fixture".utf8).write(to: primary)
        app.launchArguments = TestApplication.launchArguments(language: "fr", locale: "fr_FR")
            + ["-NSForceRightToLeftWritingDirection", "YES", "-AppleTextDirection", "YES"]
        app.launch()
        let restore = app.buttons["storage.restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: TestApplication.launchTimeout))
        XCTAssertTrue(restore.isHittable)
        XCTAssertTrue(app.buttons["storage.retry"].isHittable)
        XCTAssertGreaterThan(app.buttons["storage.retry"].frame.midX, app.buttons["storage.showFiles"].frame.midX,
                             "The actions follow the forced right-to-left direction")
        attachScreenshot("storage-recovery-french-rtl")
    }

    private var primary: URL { storage.appendingPathComponent("Browser.sqlite") }

    private func seedRecovery() throws {
        open("solid.html", expecting: "Solid fixture")
        quitAndRelaunch() // The next launch snapshot contains the saved tab.
        app.typeKey("q", modifierFlags: .command)
        XCTAssertTrue(app.groups["quit.prompt"].waitForExistence(timeout: Self.renderTimeout))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.wait(for: .notRunning, timeout: Self.pageTimeout))
        XCTAssertTrue(FileManager.default.fileExists(atPath: primary.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: storage.appendingPathComponent("Browser.recovery.sqlite").path))
        // Make a coherent standalone fixture; committed WAL pages would otherwise repair the injected corruption.
        try executeSQL("PRAGMA wal_checkpoint(TRUNCATE)")
    }

    private func restore() {
        XCTAssertTrue(app.buttons["storage.restore"].waitForExistence(timeout: Self.renderTimeout))
        app.buttons["storage.restore"].click()
        let confirmation = app.sheets.buttons["Restore previous state"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: Self.renderTimeout))
        confirmation.click()
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: TestApplication.launchTimeout))
    }

    private func setFutureVersion() throws {
        try executeSQL("PRAGMA user_version = 99")
    }

    private func executeSQL(_ sql: String) throws {
        var db: OpaquePointer?
        let status = sqlite3_open_v2(primary.path, &db, SQLITE_OPEN_READWRITE, nil)
        defer { sqlite3_close_v2(db) }
        XCTAssertEqual(status, SQLITE_OK)
        let handle = try XCTUnwrap(db)
        XCTAssertEqual(sqlite3_exec(handle, sql, nil, nil, nil), SQLITE_OK)
    }
}
