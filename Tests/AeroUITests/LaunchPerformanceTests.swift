import XCTest

/// Measures launch until the first window responds. Run with the Release configuration for
/// representative numbers; Debug builds include the preview and debug dylibs.
@MainActor
final class LaunchPerformanceTests: XCTestCase {
    func testLaunchUntilResponsive() {
        let app = TestApplication.make()
        measure(metrics: [XCTApplicationLaunchMetric(waitUntilResponsive: true)]) {
            app.launch()
        }
        app.terminate()
    }
}
