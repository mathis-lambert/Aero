import SQLite3
import XCTest

/// Loaded-page and record scaling, not a claim about physical swipe frame delivery.
@MainActor
final class SpacesPerformanceTests: BrowserE2ETestCase {
    func testManySpacesKeepLazyPagesAndStableSwitching() throws {
        quitAndRelaunch()
        app.terminate()
        let root = try XCTUnwrap(app.launchEnvironment[TestApplication.testDataKey])
        let file = URL(fileURLWithPath: root).appendingPathComponent("Storage/Browser.sqlite")
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(file.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        let handle = try XCTUnwrap(db)
        let profiles = (0..<3).map { _ in UUID().uuidString }
        var sql = "BEGIN;"
        for (i, id) in profiles.enumerated() {
            sql += "INSERT INTO profiles VALUES ('\(id)','Identity \(i)',0,\(i + 1));"
        }
        for i in 0..<12 {
            let id = UUID().uuidString
            sql += "INSERT INTO spaces VALUES ('\(id)','\(profiles[i % 3])','Space \(i)','#3366CC',NULL,\(i + 1));"
            for j in 0..<20 {
                let url = server.url("solid.html").absoluteString
                sql += "INSERT INTO tabs VALUES ('\(UUID().uuidString)','\(id)','\(url)','Fixture \(j)',NULL,'open',NULL,\(i * 20 + j));"
            }
        }
        sql += "COMMIT;"
        XCTAssertEqual(sqlite3_exec(handle, sql, nil, nil, nil), SQLITE_OK)
        app.launch()
        XCTAssertTrue(controlBarInput.waitForExistence(timeout: TestApplication.launchTimeout))
        XCTAssertEqual(app.webViews.count, 0)
        sampleResources("240-records-before-loading")
        for _ in 0..<12 {
            nextSpace()
            tabRows.firstMatch.click()
            XCTAssertTrue(page("Solid fixture").waitForExistence(timeout: Self.pageTimeout))
        }
        pause(3)
        sampleResources("12-pages-after-loading")
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTClockMetric(), XCTCPUMetric(application: app), XCTMemoryMetric(application: app)], options: options) {
            for _ in 0..<13 { nextSpace() }
        }
        pause(5)
        sampleResources("after-39-transitions")
        XCTAssertTrue(space("Space 11").isHittable, "The selected space stays visible in an overflowing footer")
        attachScreenshot("many-spaces-sidebar")
        open("video.html", expecting: "Modes inline")
        app.webViews.buttons["Play"].click()
        nextSpace()
        nextSpace()
        pause(3)
        sampleResources("background-media")
        for _ in 0..<2 {
            app.menuBars.menuBarItems["Spaces"].click()
            app.menuItems["Previous space"].click()
        }
        XCTAssertTrue(page("Modes inline picture-in-picture inline").waitForExistence(timeout: Self.pageTimeout),
                      "The background video remains live across spaces and returns from picture in picture")
    }

    private func nextSpace() {
        app.menuBars.menuBarItems["Spaces"].click()
        app.menuItems["Next space"].click()
    }

    /// The external resource sampler attributes WebKit XPC processes to this app. The runner is
    /// sandboxed and deliberately does not weaken its entitlements to inspect other processes.
    private func sampleResources(_ stage: String) {
        print("AERO_SPACES_STAGE=\(stage)")
        let attachment = XCTAttachment(string: "\(stage) at \(Date.now)")
        attachment.name = "spaces-stage-\(stage)"
        attachment.lifetime = .keepAlways
        add(attachment)
        pause(8)
    }
}
