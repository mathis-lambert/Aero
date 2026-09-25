import BrowserCore
import Foundation
import Observation
import WebKit

@MainActor @Observable
public final class BrowserPage: NSObject, WKNavigationDelegate, WKUIDelegate {
    static let firstFrameTimeout = Duration.milliseconds(1500)

    public let webView: WKWebView
    public private(set) var isLoading = false
    public private(set) var progress = 0.0
    public private(set) var canGoBack = false
    public private(set) var canGoForward = false
    public private(set) var failure: PageFailure?
    /// False until the first document has rendered a frame; later navigations keep it true.
    public private(set) var hasRenderedFirstFrame = false

    public enum PageFailure { case loadFailed, processTerminated, unsupportedNavigation }

    /// Set by the registry, which owns the tab identity behind each event.
    @ObservationIgnored var onMetadata: ((URL, String) -> Void)?
    @ObservationIgnored var onIcons: (([FaviconLink], URL) -> Void)?
    @ObservationIgnored var onPopup: ((WKWebViewConfiguration, URL?) -> WKWebView?)?
    @ObservationIgnored var onClose: (() -> Void)?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var requestedURL: URL?
    @ObservationIgnored private var firstFrameTimeout: Task<Void, Never>?

    static func configuration(store: WKWebsiteDataStore) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .audio
        configuration.userContentController.addUserScript(PageScripts.editedFieldTracker)
        return configuration
    }

    init(configuration: WKWebViewConfiguration) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        #if DEBUG
        webView.isInspectable = true
        #endif
        observations = [
            webView.observe(\.estimatedProgress) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
            webView.observe(\.isLoading) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
            webView.observe(\.canGoBack) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
            webView.observe(\.canGoForward) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
            webView.observe(\.title) { [weak self] _, _ in Task { @MainActor in self?.refresh() } },
            webView.observe(\.url) { [weak self] _, _ in Task { @MainActor in self?.refresh() } }
        ]
    }

    public func load(_ url: URL) {
        guard NavigationInput.isWebURL(url) else { fail(.unsupportedNavigation); return }
        failure = nil
        requestedURL = url
        webView.load(URLRequest(url: url))
    }

    /// Returns to a hibernated page's history and scroll position without an extra network request.
    func restore(_ interactionState: Any, url: URL) {
        failure = nil
        requestedURL = url
        webView.interactionState = interactionState
    }

    public func reload() {
        failure = nil
        if webView.url != nil { webView.reload() }
        else if let requestedURL { load(requestedURL) }
    }
    public func stop() { webView.stopLoading() }
    public func goBack() { failure = nil; webView.goBack() }
    public func goForward() { failure = nil; webView.goForward() }

    func dispose() {
        onMetadata = nil
        onIcons = nil
        onPopup = nil
        onClose = nil
        firstFrameTimeout?.cancel()
        observations.removeAll()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
    }

    private func refresh() {
        isLoading = webView.isLoading
        progress = webView.estimatedProgress
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        if let url = webView.url, NavigationInput.isWebURL(url) { onMetadata?(url, webView.title ?? "") }
    }

    private func fail(_ failure: PageFailure) {
        self.failure = failure
        revealFirstFrame()
    }

    // MARK: - First frame

    /// Waits for two animation frames of the committed document, which only resolve once WebKit
    /// has produced a frame; the timeout reveals pages that never schedule one.
    private func awaitFirstFrame() {
        guard !hasRenderedFirstFrame, firstFrameTimeout == nil else { return }
        firstFrameTimeout = Task { [weak self] in
            do { try await Task.sleep(for: Self.firstFrameTimeout) } catch { return }
            self?.revealFirstFrame()
        }
        Task { [weak self, webView] in
            // Either outcome reveals the page: a script failure must not leave it hidden.
            _ = try? await webView.callAsyncJavaScript(PageScripts.nextFrame, contentWorld: PageScripts.world)
            self?.revealFirstFrame()
        }
    }

    private func revealFirstFrame() {
        guard !hasRenderedFirstFrame else { return }
        hasRenderedFirstFrame = true
        firstFrameTimeout?.cancel()
        firstFrameTimeout = nil
    }

    // MARK: - Icons

    private func readDeclaredIcons() {
        guard let pageURL = webView.url, NavigationInput.isWebURL(pageURL) else { return }
        Task { [weak self, webView] in
            let result = try? await webView.callAsyncJavaScript(PageScripts.declaredIcons, contentWorld: PageScripts.world)
            // The page may have navigated while the script ran; its icons belong to the old URL.
            guard let self, webView.url == pageURL else { return }
            self.onIcons?(PageScripts.iconLinks(from: result), pageURL)
        }
    }

    // MARK: - WKNavigationDelegate

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        failure = nil
        refresh()
    }

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) { awaitFirstFrame() }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refresh()
        readDeclaredIcons()
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        if (error as NSError).code != NSURLErrorCancelled { fail(.loadFailed) }
        refresh()
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        if (error as NSError).code != NSURLErrorCancelled { fail(.loadFailed) }
        refresh()
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        fail(.processTerminated)
        refresh()
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        // Frame-local blob/about documents are legitimate; never launch external schemes implicitly.
        if NavigationInput.isWebURL(url) || ["about", "blob"].contains(url.scheme ?? "") { return .allow }
        if navigationAction.targetFrame?.isMainFrame != false { fail(.unsupportedNavigation) }
        return .cancel
    }

    // MARK: - WKUIDelegate

    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        onPopup?(configuration, navigationAction.request.url)
    }

    public func webViewDidClose(_ webView: WKWebView) { onClose?() }
}
