import XCTest

/// CPU consumed after an onboarding interaction has settled. The frame-state rules are tested by
/// WindMotionTests; this measurement observes the real SwiftUI timeline in Release.
@MainActor
final class OnboardingPerformanceTests: E2ETestCase {
    func testOnboardingAtRest() throws {
        try launch(Launch(screen: .onboarding))
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["onboarding.source.Google Chrome"].waitForExistence(timeout: Self.renderTimeout))
        app.menuBars.menuBarItems.firstMatch.hover()
        // The 20-second inactivity deadline and any final gust must pass before measuring idle work.
        pause(25)
        let options = XCTMeasureOptions()
        options.iterationCount = 1
        measure(metrics: [XCTCPUMetric(application: app)], options: options) { pause(5) }
        attachScreenshot("onboarding at rest")
    }
}
