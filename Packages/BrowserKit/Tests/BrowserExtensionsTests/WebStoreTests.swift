import Testing
@testable import BrowserExtensions

@Test func storeInputAcceptsAnIDOrAnOfficialSecureLink() {
    let id = "ghmbeldphafepmbegfdlkpapadhbakde"
    #expect(WebStore.extensionID(in: " \(id)\n") == id)
    #expect(WebStore.extensionID(in: "https://chromewebstore.google.com/detail/example-extension/\(id)") == id)
    for input in ["bad", "http://chromewebstore.google.com/detail/\(id)",
                  "https://chromewebstore.google.com.evil.test/detail/\(id)",
                  "https://user@chromewebstore.google.com/detail/\(id)", "https://chromewebstore.google.com/search/\(id)"] {
        #expect(WebStore.extensionID(in: input) == nil)
    }
}
