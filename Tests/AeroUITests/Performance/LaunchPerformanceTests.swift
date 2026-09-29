import XCTest

/// Launch until the first window responds. Run the Performance plan with the Release configuration for
/// representative numbers; Debug builds include the preview and debug dylibs. See docs/PERFORMANCE.md.
@MainActor
final class LaunchPerformanceTests: E2ETestCase {
    func testLaunchUntilResponsive() {
        app.launchArguments = Launch().arguments
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)]) { app.launch() }
    }
}
