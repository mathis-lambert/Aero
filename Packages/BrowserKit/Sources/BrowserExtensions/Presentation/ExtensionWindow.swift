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
        let size = frame.isNull || frame.size.width < Self.minimumSize.width || frame.size.height < Self.minimumSize.height ? Self.defaultSize : frame.size
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.contentMinSize = Self.minimumSize
        window.contentView = webView
        window.delegate = self
        window.title = owner.contexts[extensionID]?.webExtension.displayName ?? ""
        if frame.isNull || frame.origin == .zero { window.center() } else { window.setFrameOrigin(frame.origin) }
        webView.navigationDelegate = self
        webView.uiDelegate = self
        #if DEBUG
        webView.isInspectable = true
        #endif
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
    func isPrivate(for context: WKWebExtensionContext) -> Bool { false }
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

/// The page of an extension's popup window, as WebKit presents it to extensions.
final class ExtensionWindowTab: NSObject, WKWebExtensionTab {
    unowned let owner: ExtensionWindow

    init(owner: ExtensionWindow) { self.owner = owner }

    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { owner }
    func indexInWindow(for context: WKWebExtensionContext) -> Int { 0 }
    func title(for context: WKWebExtensionContext) -> String? { owner.webView.title }
    func url(for context: WKWebExtensionContext) -> URL? { owner.webView.url }
    func isSelected(for context: WKWebExtensionContext) -> Bool { true }
    func webView(for context: WKWebExtensionContext) -> WKWebView? { owner.webView }
    func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !owner.webView.isLoading }
    func zoomFactor(for context: WKWebExtensionContext) -> Double { owner.webView.pageZoom }
    func size(for context: WKWebExtensionContext) -> CGSize { owner.webView.bounds.size }

    func activate(for context: WKWebExtensionContext) async throws { owner.show(focused: true) }
    func close(for context: WKWebExtensionContext) async throws { owner.close() }
    func loadURL(_ url: URL, for context: WKWebExtensionContext) async throws { owner.webView.load(URLRequest(url: url)) }
    func reload(fromOrigin: Bool, for context: WKWebExtensionContext) async throws {
        if fromOrigin { owner.webView.reloadFromOrigin() } else { owner.webView.reload() }
    }
    func goBack(for context: WKWebExtensionContext) async throws { owner.webView.goBack() }
    func goForward(for context: WKWebExtensionContext) async throws { owner.webView.goForward() }
    func setZoomFactor(_ zoomFactor: Double, for context: WKWebExtensionContext) async throws { owner.webView.pageZoom = zoomFactor }

    func snapshot(using configuration: WKSnapshotConfiguration, for context: WKWebExtensionContext) async throws -> NSImage? {
        try await owner.webView.takeSnapshot(configuration: configuration)
    }
}
