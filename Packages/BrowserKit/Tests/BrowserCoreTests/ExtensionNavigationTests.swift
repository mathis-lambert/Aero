import Foundation
import Testing
@testable import BrowserCore

@Test func chromeAndWebKitExtensionPagesAreNavigableTabs() throws {
    for address in ["chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/connection.html", "webkit-extension://example/options.html"] {
        let url = try #require(URL(string: address))
        #expect(NavigationInput.isExtensionURL(url))
        #expect(NavigationInput.isTabURL(url))
        #expect(NavigationInput.target(of: url) == .page)
    }
    let invalid = try #require(URL(string: "chrome-extension:///private.html"))
    #expect(!NavigationInput.isExtensionURL(invalid))
    #expect(NavigationInput.target(of: invalid) == .blocked)
}
