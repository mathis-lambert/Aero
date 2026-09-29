import BrowserCore
import Foundation
import Testing

// Where a page's navigation goes; see docs/OTHER_APPS.md › Links to other apps. Failure modes:
// 1. A website reaches local files, scripts, inline data or the browser's own pages.
// 2. A link meant for another app (a sign-in callback, mail, a meeting) is dropped as unsupported.
// 3. A malformed web address is handed to another app instead of being refused.
// 4. Scheme case changes the answer.

private func target(_ address: String) throws -> NavigationTarget {
    NavigationInput.target(of: try #require(URL(string: address)))
}

@Test func pagesLoadInPlace() throws {
    for address in ["https://example.com/a", "http://localhost:8080", "HTTPS://Example.com", "about:blank", "about:srcdoc",
                    "blob:https://example.com/0f6c", "webkit-extension://abc/options.html"] {
        #expect(try target(address) == .page, "\(address)")
    }
}

@Test func otherAppsAreAskedFor() throws {
    for address in ["mailto:someone@example.com", "tel:+33100000000", "proton-pass://callback?code=1", "zoommtg://zoom.us/join",
                    "MAILTO:someone@example.com", "x-apple.systempreferences:com.apple.preference.security", "com.example.app:/oauth"] {
        #expect(try target(address) == .application, "\(address)")
    }
}

@Test func websitesNeverReachLocalOrPrivilegedSchemes() throws {
    for address in ["file:///etc/hosts", "javascript:alert(1)", "JavaScript:alert(1)", "data:text/html,<b>x</b>", "vbscript:x",
                    "aero://history", "AERO://settings", "https:", "https:///path", "http://", "webkit-extension:///page"] {
        #expect(try target(address) == .blocked, "\(address)")
    }
}
