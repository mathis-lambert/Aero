import AppKit
import Foundation
import Testing
import WebKit

// What WebKit's extension engine does on its own, without Aero's layer. Each test keeps a divergence from Chrome's
// contract that the layer fixes, or shows that WebKit already does what Aero leaves to it. When one fails, WebKit
// changed: remove the matching fix, or bring it back. Needs access to macOS WebKit services.

private let manifest = """
    {"manifest_version":3,"name":"Native baseline","version":"1","action":{"default_popup":"popup.html"},
     "background":{"service_worker":"worker.js"},"permissions":["tabs","clipboardWrite","clipboardRead"],
     "host_permissions":["<all_urls>"],"commands":{"_execute_action":{"suggested_key":{"default":"Ctrl+Shift+Y"}}}}
    """
private let files = [
    "worker.js": "chrome.runtime.onMessage.addListener((message, sender, reply) => { if (message === 'idle') reply(typeof requestIdleCallback); });",
    "page.html": "<html><body><input id='field' value='selected text'></body></html>",
    "popup.html": "<html><body>Popup</body></html>"
]

@MainActor
private func evaluate(_ view: WKWebView, _ body: String) async throws -> Any? {
    try await view.callAsyncJavaScript(body, contentWorld: .page)
}

/// WebKit delivers to a context through its `browser` or `chrome` global: once a script replaces both, even with a
/// wrapper of the native namespace, its listeners hear nothing. WebKitRuntime.js keeps the globals.
@MainActor
@Test func replacingBothGlobalsCutsWebKitOffTheListeners() async throws {
    let native = try await NativeExtension(manifest: manifest, files: files)
    defer { native.close() }
    let listener = try await native.page("page.html")
    _ = try await evaluate(listener, """
        const runtime = chrome.runtime;
        runtime.onMessage.addListener((message, sender, reply) => { if (message === 'one') reply('heard'); });
        return true;
        """)
    let sender = try await native.page("page.html")
    #expect(try await evaluate(sender, "return String(await chrome.runtime.sendMessage('one'))") as? String == "heard")
    _ = try await evaluate(listener, "const wrapper = new Proxy(chrome, {}); globalThis.browser = wrapper; globalThis.chrome = wrapper; return true;")
    #expect(try await evaluate(sender, "return String(await chrome.runtime.sendMessage('one'))") as? String == "undefined")
}

/// WebKit recreates its `runtime` namespace once nothing references it, without what a script added. Bootstrap.js
/// keeps the namespaces it extends referenced.
@MainActor
@Test func garbageCollectionDropsAdditionsToRuntime() async throws {
    let native = try await NativeExtension(manifest: manifest, files: files)
    defer { native.close() }
    let page = try await native.page("page.html")
    _ = try await evaluate(page, "chrome.runtime.addition = 1; return true;")
    let dropped = try await NativeExtension.until(.seconds(10)) {
        try await evaluate(page, """
            for (let round = 0; round < 40; round += 1) new Array(300000).fill(round);
            await new Promise((resolve) => setTimeout(resolve, 100));
            return chrome.runtime.addition === undefined;
            """) as? Bool == true
    }
    #expect(dropped)
}

/// Neither extension pages nor workers have idle callbacks. WebKitRuntime.js adds them to pages.
@MainActor
@Test func extensionPagesHaveNoIdleCallbacks() async throws {
    let native = try await NativeExtension(manifest: manifest, files: files)
    defer { native.close() }
    let page = try await native.page("page.html")
    #expect(try await evaluate(page, "return typeof requestIdleCallback") as? String == "undefined")
    #expect(try await evaluate(page, "return await chrome.runtime.sendMessage('idle')") as? String == "undefined")
}

/// The `_execute_action` command performs the action through WebKit: the popup is presented without Aero's help.
/// WebKit then gives the popup its tab, where Chrome gives it none; Tabs.js answers nothing there.
@MainActor
@Test func theActionCommandPresentsAPopupThatWebKitGivesATab() async throws {
    let native = try await NativeExtension(manifest: manifest, files: files)
    defer { native.close() }
    let command = try #require(native.context.commands.first { $0.id == "_execute_action" })
    native.context.performCommand(command)
    #expect(try await NativeExtension.until { native.presentedPopup?.popupWebView != nil })
    let popup = try #require(native.presentedPopup?.popupWebView)
    try await NativeExtension.waitUntilLoaded(popup)
    #expect(try await evaluate(popup, "return (await chrome.tabs.getCurrent()) !== undefined") as? Bool == true)
}

/// `<all_urls>` reaches every registered extension scheme, so another extension's pages. ExtensionSiteAccess denies them.
@MainActor
@Test func allURLsReachesOtherExtensions() async throws {
    let native = try await NativeExtension(manifest: manifest, files: files)
    defer { native.close() }
    #expect(native.context.hasAccess(to: try #require(URL(string: "chrome-extension://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/private.html"))))
    #expect(native.context.hasAccess(to: try #require(URL(string: "webkit-extension://bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/private.html"))))
}

/// An extension page writes and copies without a window or focus, as an offscreen document does, and reads back what
/// it wrote: Aero adds nothing there. (Reading what another app copied blocks the page on WebKit's paste confirmation,
/// where Chrome's `clipboardRead` reads at once: ExtensionSystemServicesTests covers Aero's reading.)
@MainActor
@Test func extensionPagesUseTheClipboardWithoutFocus() async throws {
    let native = try await NativeExtension(manifest: manifest, files: files)
    defer { native.close() }
    let page = try await native.page("page.html")
    try await SharedPasteboard.use { pasteboard in
        _ = try await evaluate(page, "await navigator.clipboard.writeText('written'); return true;")
        #expect(pasteboard.string(forType: .string) == "written")
        #expect(try await evaluate(page, "return await navigator.clipboard.readText()") as? String == "written")
        #expect(try await evaluate(page, "const field = document.getElementById('field'); field.focus(); field.select(); return document.execCommand('copy');") as? Bool == true)
        #expect(pasteboard.string(forType: .string) == "selected text")
    }
}
