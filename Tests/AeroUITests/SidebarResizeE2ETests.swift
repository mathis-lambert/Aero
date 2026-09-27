import XCTest

@MainActor
final class SidebarResizeE2ETests: BrowserE2ETestCase {
    func testResizeLimitsCollapseAndPersistence() {
        let handle = app.descendants(matching: .any).matching(identifier: "sidebar.resize").firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: Self.renderTimeout))
        let initial = width(of: handle)
        drag(handle, by: 80)
        XCTAssertTrue(poll { self.width(of: handle) > initial + 65 })
        let expanded = width(of: handle)
        relaunch()
        XCTAssertTrue(poll { abs(self.width(of: handle) - expanded) < 3 })

        drag(handle, by: 500)
        let window = app.windows.firstMatch.frame
        XCTAssertEqual(handle.frame.maxX - window.minX, window.width / 3, accuracy: 3)
        drag(handle, by: -(width(of: handle) - initial + 30))
        XCTAssertEqual(width(of: handle), initial, accuracy: 3)

        drag(handle, by: -190)
        // Move away from the reveal edge before checking the folded state.
        app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).hover()
        XCTAssertTrue(poll { !handle.exists })
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(handle.waitForExistence(timeout: Self.renderTimeout))
        XCTAssertEqual(width(of: handle), initial, accuracy: 3)
        attachScreenshot("sidebar-resized", of: app)
    }

    private func width(of handle: XCUIElement) -> CGFloat {
        handle.frame.maxX - app.windows.firstMatch.frame.minX
    }

    private func drag(_ handle: XCUIElement, by offset: CGFloat) {
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.click(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: offset, dy: 0)))
    }
}
