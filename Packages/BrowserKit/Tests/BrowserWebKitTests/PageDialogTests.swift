import Foundation
import Testing
import WebKit
@testable import BrowserWebKit

// Failure modes: a page's `alert`, `confirm` or `prompt` does nothing (WebKit shows no dialog of its own on macOS), the
// dialog names a site the page claims rather than its frame's, a page that keeps asking cannot be stopped, or a stop
// outlives its document. Needs access to macOS WebKit services.
@MainActor
@Test func pageDialogsReachTheBrowserAndCanBeStopped() async throws {
    let page = BrowserPage(configuration: BrowserPage.configuration(store: .nonPersistent()))
    var asked: [PageDialog] = []
    var answer = PageDialogAnswer(accepted: true, text: "typed")
    page.onDialog = { dialog in
        asked.append(dialog)
        return answer
    }
    func load() async throws {
        page.webView.loadHTMLString("<title>Dialogs</title>", baseURL: URL(string: "https://dialogs.example/"))
        let deadline = ContinuousClock.now + .seconds(10)
        while page.webView.isLoading || page.webView.url == nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
    }
    func run(_ script: String) async throws -> Any? { try await page.webView.callAsyncJavaScript(script, contentWorld: .page) }
    try await load()

    #expect(try await run("return confirm('Leave?')") as? Bool == true)
    #expect(asked.last?.kind == .confirm && asked.last?.message == "Leave?" && asked.last?.site == "dialogs.example")
    #expect(asked.last?.offersSuppression == false, "A first dialog offers no way to stop the page")
    #expect(try await run("return prompt('Name?', 'Ada')") as? String == "typed")
    #expect(asked.last?.kind == .prompt(defaultText: "Ada") && asked.last?.offersSuppression == true)
    _ = try await run("alert('x'.repeat(5000)); return true")
    #expect(asked.last?.message.count == PageDialog.maximumLength)

    answer = PageDialogAnswer(accepted: false, suppressesMore: true)
    #expect(try await run("return prompt('Again?') === null") as? Bool == true, "A cancelled prompt answers null")
    let count = asked.count
    #expect(try await run("return confirm('Still?')") as? Bool == false)
    #expect(asked.count == count, "A stopped page asks no more")

    answer = PageDialogAnswer(accepted: true)
    try await load()
    #expect(try await run("return confirm('New document')") as? Bool == true, "A new document may ask again")
    #expect(asked.count == count + 1)
}
