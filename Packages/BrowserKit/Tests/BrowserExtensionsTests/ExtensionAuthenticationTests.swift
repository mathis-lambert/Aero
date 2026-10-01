import Foundation
import Testing
import WebKit
@testable import BrowserExtensions

// Failure modes: cross-extension redirects, credential/port tricks, malformed requests,
// a silent flow that needs interaction, and cancellation that leaves a request pending.
@MainActor
@Test func authorizationRedirectBelongsToOneExtension() throws {
    let id = String(repeating: "a", count: 32)
    for address in ["https://\(id).chromiumapp.org/?code=example", "https://\(id).chromiumapp.org:443/finish#example"] {
        #expect(ExtensionAuthentication.isRedirect(try #require(URL(string: address)), for: id))
    }
    for address in ["https://bbbb.chromiumapp.org/", "https://\(id).chromiumapp.org.attacker.test/", "http://\(id).chromiumapp.org/",
                    "https://\(id).chromiumapp.org:444/", "https://user@\(id).chromiumapp.org/"] {
        #expect(!ExtensionAuthentication.isRedirect(try #require(URL(string: address)), for: id))
    }
}

@MainActor
@Test func invalidAuthorizationRequestsAreRejected() {
    for body: [String: Any] in [["url": "file:///etc/hosts"], ["url": "https://user@example.test/"],
                                ["url": "https://example.test/", "timeoutMsForNonInteractive": -1],
                                ["url": "https://example.test/", "timeoutMsForNonInteractive": Double.infinity],
                                ["url": "https://example.test/", "timeoutMsForNonInteractive": "later"],
                                ["url": "https://example.test/", "interactive": 1]] {
        #expect(throws: (any Error).self) { try ExtensionAuthentication.Options(body) }
    }
}

@MainActor
@Test func cancellingAuthorizationEndsItsRequest() async throws {
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    let flow = try ExtensionAuthentication(identifier: String(repeating: "a", count: 32),
                                           options: .init(["url": "https://example.invalid/", "interactive": true]),
                                           configuration: configuration, title: "Authorization fixture")
    let request = Task { try await flow.run() }
    request.cancel()
    await #expect(throws: CancellationError.self) { try await request.value }
}

@Test func identityUsesBrowserContractsWithoutAnAccount() async throws {
    let harness = try CompatibilityHarness(manifest: #"{"permissions":["identity","identity.email"]}"#)
    #expect(harness.string("chrome.identity.getRedirectURL('finish')") == "https://" + String(repeating: "a", count: 32) + ".chromiumapp.org/finish")
    harness.run("replies['identity/profile'] = {email:'',id:''}; chrome.identity.getProfileUserInfo().then(value => globalThis.profile = value)")
    let deadline = ContinuousClock.now + .seconds(2)
    while !harness.bool("globalThis.profile !== undefined"), ContinuousClock.now < deadline { await Task.yield() }
    #expect(harness.string("JSON.stringify(profile)") == #"{"email":"","id":""}"#)
    harness.run("chrome.identity.launchWebAuthFlow({url:'https://example.test/',interactive:true})")
    while !harness.bool("requests.some(value => value.route === 'identity/launch')"), ContinuousClock.now < deadline { await Task.yield() }
    #expect(harness.bool("requests.some(value => value.route === 'identity/launch' && value.body.interactive === true)"))
}

@MainActor
@Test(arguments: [false, true])
func webAuthorizationReturnsTheProviderRedirect(scripted: Bool) async throws {
    let id = String(repeating: "a", count: 32)
    let redirect = "https://\(id).chromiumapp.org/finish?code=fixture#state"
    let html = "<script>location.replace('\(redirect)')</script>"
    let response = scripted
        ? "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        : "HTTP/1.1 302 Found\r\nLocation: \(redirect)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    let provider = try AuthorizationServer(response: response)
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    let flow = try ExtensionAuthentication(identifier: id,
                                           options: .init(["url": provider.url.absoluteString, "abortOnLoadForNonInteractive": false,
                                                           "timeoutMsForNonInteractive": 5000]), configuration: configuration, title: "Provider fixture")
    #expect(try await flow.run() == redirect)
    let deadline = ContinuousClock.now + .seconds(2)
    while flow.webView.isLoading, ContinuousClock.now < deadline { await Task.yield() }
    #expect(!flow.webView.isLoading)
}

@MainActor
@Test func silentAuthorizationRefusesAPageThatNeedsInteraction() async throws {
    let provider = try AuthorizationServer(response: "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 5\r\nConnection: close\r\n\r\nLogin")
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    let flow = try ExtensionAuthentication(identifier: String(repeating: "a", count: 32), options: .init(["url": provider.url.absoluteString]),
                                           configuration: configuration, title: "Provider fixture")
    await #expect(throws: (any Error).self) { try await flow.run() }
}

// A provider's popup communicates through window.opener before the primary view redirects.
// Flattening it into the primary view loses the opener and cannot finish this example.
@MainActor
@Test func authorizationProviderKeepsItsNativeOpener() async throws {
    let id = String(repeating: "a", count: 32), redirect = "https://\(String(repeating: "a", count: 32)).chromiumapp.org/finish?opener=preserved"
    let html = """
        <script>
        if (window.opener) { window.opener.postMessage('ready', location.origin); window.close(); }
        else { window.addEventListener('message', event => { if (event.origin === location.origin && event.data === 'ready') location.replace('\(redirect)'); }); window.open('/popup'); }
        </script>
        """
    let provider = try AuthorizationServer(response: "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)")
    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
    let flow = try ExtensionAuthentication(identifier: id,
                                           options: .init(["url": provider.url.absoluteString, "abortOnLoadForNonInteractive": false,
                                                           "timeoutMsForNonInteractive": 5000]), configuration: configuration, title: "Opener fixture")
    #expect(try await flow.run() == redirect)
}
