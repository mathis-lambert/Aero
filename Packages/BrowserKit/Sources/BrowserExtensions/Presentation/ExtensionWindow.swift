import AppKit
import BrowserCore
import WebKit

/// A `windows.create` popup with one page using the profile's data. Closing the window ends its page.
@MainActor
final class ExtensionWindow: NSObject, WKWebExtensionWindow, NSWindowDelegate {
    static let defaultSize = CGSize(width: 400, height: 600)
    static let minimumSize = CGSize(width: 240, height: 200)

    let extensionID: String
    /// Names the window's page in `runtime.getContexts`.
    let id = UUID()
    let window: NSWindow
    let webView: WKWebView
    private(set) lazy var tab = ExtensionWindowTab(owner: self)
    private unowned let owner: ProfileExtensions
    private var titleObservation: NSKeyValueObservation?
    private var isClosed = false

    init(extensionID: String, url: URL, configuration: WKWebViewConfiguration, frame: CGRect, owner: ProfileExtensions) {
        self.extensionID = extensionID
        self.owner = owner
        webView = WKWebView(frame: .zero, configuration: configuration)
        // WebKit leaves each component the extension did not give as NaN; a given size is clamped, as Chrome does.
        let size = CGSize(width: frame.width.isNaN ? Self.defaultSize.width : max(frame.width, Self.minimumSize.width),
                          height: frame.height.isNaN ? Self.defaultSize.height : max(frame.height, Self.minimumSize.height))
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.contentMinSize = Self.minimumSize
        window.contentView = webView
        window.delegate = self
        window.title = owner.contexts[extensionID]?.webExtension.displayName ?? ""
        window.center()
        var origin = window.frame.origin
        if !frame.origin.x.isNaN { origin.x = frame.origin.x }
        if !frame.origin.y.isNaN { origin.y = frame.origin.y }
        window.setFrameOrigin(origin)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.isInspectable = owner.isInspectable
        titleObservation = webView.observe(\.title) { [weak self] webView, _ in
            MainActor.assumeIsolated {
                guard let self, let title = webView.title, !title.isEmpty else { return }
                self.window.title = title
                self.owner.controller.didChangeTabProperties(.title, for: self.tab)
            }
        }
        webView.load(URLRequest(url: url))
    }

    func show(focused: Bool) {
        if focused {
            NSApplication.shared.activate()
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFront(nil)
        }
    }

    /// Ends the window and its page, from either side, once.
    func close() {
        guard !isClosed else { return }
        isClosed = true
        titleObservation = nil
        window.delegate = nil
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.stopLoading()
        window.close()
        owner.windowDidClose(self)
    }

    func windowWillClose(_ notification: Notification) { close() }

    // MARK: - WKWebExtensionWindow

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] { [tab] }
    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? { tab }
    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType { .popup }
    func frame(for context: WKWebExtensionContext) -> CGRect { window.frame }
    func screenFrame(for context: WKWebExtensionContext) -> CGRect { window.screen?.frame ?? NSScreen.main?.frame ?? .null }

    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
        window.isMiniaturized ? .minimized : window.isZoomed ? .maximized : .normal
    }

    func setWindowState(_ state: WKWebExtension.WindowState, for context: WKWebExtensionContext) async throws {
        switch state {
        case .minimized: window.miniaturize(nil)
        case .maximized: if !window.isZoomed { window.zoom(nil) }
        case .normal:
            if window.isMiniaturized { window.deminiaturize(nil) } else if window.isZoomed { window.zoom(nil) }
        case .fullscreen: throw ExtensionRequestFailure.unsupported("A full screen popup window")
        @unknown default: break
        }
    }

    func setFrame(_ frame: CGRect, for context: WKWebExtensionContext) async throws { window.setFrame(frame, display: true, animate: false) }
    func focus(for context: WKWebExtensionContext) async throws { show(focused: true) }
    func close(for context: WKWebExtensionContext) async throws { close() }
}

extension ExtensionWindow: WKNavigationDelegate, WKUIDelegate {
    /// Only pages load here; anything else, such as another app's address, is not followed.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        return NavigationInput.target(of: url) == .page ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        owner.controller.didChangeTabProperties([.URL, .loading], for: tab)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        owner.controller.didChangeTabProperties(.loading, for: tab)
    }

    /// Links that open a new window open in a tab of the main window.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, NavigationInput.isWebURL(url) {
            _ = owner.host?.openTab(url, inProfile: owner.profileID, selected: true)
        }
        return nil
    }

    func webViewDidClose(_ webView: WKWebView) { close() }
}

/// The page of an extension's popup window, as WebKit presents it to extensions. Title, address, loading, size, zoom,
/// navigation and snapshots are WebKit's defaults, read from and applied to `webView`.
final class ExtensionWindowTab: NSObject, WKWebExtensionTab {
    unowned let owner: ExtensionWindow

    init(owner: ExtensionWindow) { self.owner = owner }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { owner }
    func indexInWindow(for context: WKWebExtensionContext) -> Int { 0 }
    func webView(for context: WKWebExtensionContext) -> WKWebView? { owner.webView }
    func activate(for context: WKWebExtensionContext) async throws { owner.show(focused: true) }
    func close(for context: WKWebExtensionContext) async throws { owner.close() }
}
