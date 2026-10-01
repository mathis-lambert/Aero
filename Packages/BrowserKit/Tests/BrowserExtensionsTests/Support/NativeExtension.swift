import AppKit
import Foundation
import Testing
import WebKit

/// An extension loaded in WebKit's engine alone, without Aero's package preparation or compatibility layer, so a test
/// observes what WebKit itself does. Its one window and tab are a visible `NSWindow` and the page shown in it.
@MainActor
final class NativeExtension: NSObject, WKWebExtensionControllerDelegate, WKWebExtensionWindow, WKWebExtensionTab {
    let folder: URL
    let controller = WKWebExtensionController(configuration: .nonPersistent())
    let context: WKWebExtensionContext
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: false)
    /// The website page of the tab.
    let tabView: WKWebView
    private(set) var presentedPopup: WKWebExtension.Action?
    private var views: [WKWebView] = []

    /// `files` maps package paths to their contents; `permissions` are granted as the manifest declares them.
    init(manifest: String, files: [String: String]) async throws {
        folder = FileManager.default.temporaryDirectory.appending(path: "aero-native-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(manifest.utf8).write(to: folder.appending(path: "manifest.json"))
        for (path, contents) in files { try Data(contents.utf8).write(to: folder.appending(path: path)) }
        let webExtension = try await WKWebExtension(resourceBaseURL: folder)
        WKWebExtension.MatchPattern.registerCustomURLScheme("chrome-extension")
        context = WKWebExtensionContext(for: webExtension)
        context.baseURL = try #require(URL(string: "chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/"))
        for permission in webExtension.requestedPermissions { context.setPermissionStatus(.grantedExplicitly, for: permission) }
        for pattern in webExtension.allRequestedMatchPatterns { context.setPermissionStatus(.grantedExplicitly, for: pattern) }
        let configuration = WKWebViewConfiguration()
        configuration.webExtensionController = controller
        configuration.websiteDataStore = .nonPersistent()
        tabView = WKWebView(frame: window.contentLayoutRect, configuration: configuration)
        super.init()
        window.isReleasedWhenClosed = false
        window.contentView = tabView
        window.orderFront(nil)
        controller.delegate = self
        try controller.load(context)
        controller.didOpenWindow(self)
        controller.didOpenTab(self)
        controller.didActivateTab(self, previousActiveTab: nil)
        controller.didFocusWindow(self)
    }

    func close() {
        try? controller.unload(context)
        window.close()
        try? FileManager.default.removeItem(at: folder)
    }

    /// An extension page in a view of its own, loaded; `inWindow` puts it in a window of its own, otherwise it has none.
    func page(_ path: String, inWindow: Bool = false) async throws -> WKWebView {
        let configuration = try #require(context.webViewConfiguration)
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 400, height: 300), configuration: configuration)
        views.append(view)
        if inWindow {
            let pageWindow = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
            pageWindow.isReleasedWhenClosed = false
            pageWindow.contentView = view
            pageWindow.makeKeyAndOrderFront(nil)
        }
        view.load(URLRequest(url: context.baseURL.appending(path: path)))
        try await Self.waitUntilLoaded(view)
        return view
    }

    static func waitUntilLoaded(_ view: WKWebView) async throws {
        let deadline = ContinuousClock.now + .seconds(15)
        while view.isLoading || view.url == nil, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
    }

    /// Waits until `condition` holds, for what WebKit reports asynchronously.
    static func until(_ timeout: Duration = .seconds(15), _ condition: () async throws -> Bool) async throws -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if try await condition() { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return try await condition()
    }

    // MARK: - WKWebExtensionControllerDelegate

    func webExtensionController(_ controller: WKWebExtensionController, openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] { [self] }
    func webExtensionController(_ controller: WKWebExtensionController, focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { self }

    func webExtensionController(_ controller: WKWebExtensionController, presentActionPopup action: WKWebExtension.Action,
                                for context: WKWebExtensionContext) async throws {
        presentedPopup = action
        guard let anchor = window.contentView else { return }
        action.popupPopover?.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }

    // MARK: - WKWebExtensionWindow

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] { [self] }
    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? { self }
    func frame(for context: WKWebExtensionContext) -> CGRect { window.frame }

    // MARK: - WKWebExtensionTab

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { self }
    func webView(for context: WKWebExtensionContext) -> WKWebView? { tabView }
}
