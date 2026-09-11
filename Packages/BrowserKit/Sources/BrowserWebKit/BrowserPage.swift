import BrowserCore
import Foundation
import Observation
import WebKit

@MainActor @Observable
public final class BrowserPage: NSObject, WKNavigationDelegate, WKUIDelegate {
    public let webView: WKWebView
    public private(set) var isLoading = false
    public private(set) var progress = 0.0
    public private(set) var canGoBack = false
    public private(set) var canGoForward = false
    public private(set) var title = ""
    public private(set) var url: URL?
    public private(set) var failure: PageFailure?

    public enum PageFailure { case loadFailed, processTerminated, unsupportedNavigation }

    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var onMetadata: (@MainActor (URL, String) -> Void)?
    @ObservationIgnored private var onOpen: (@MainActor (URL) -> Void)?
    @ObservationIgnored private var requestedURL: URL?

    init(store: WKWebsiteDataStore, onMetadata: @escaping @MainActor (URL, String) -> Void, onOpen: @escaping @MainActor (URL) -> Void) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .audio
        configuration.userContentController.addUserScript(PageScripts.editedFieldTracker)
        webView = WKWebView(frame: .zero, configuration: configuration)
        self.onMetadata = onMetadata
        self.onOpen = onOpen
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
        guard NavigationInput.isWebURL(url) else { failure = .unsupportedNavigation; return }
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
        onOpen = nil
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
        title = webView.title ?? ""
        url = webView.url
        if let url, NavigationInput.isWebURL(url) { onMetadata?(url, title) }
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        failure = nil
        refresh()
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { refresh() }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        if (error as NSError).code != NSURLErrorCancelled { failure = .loadFailed }
        refresh()
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        if (error as NSError).code != NSURLErrorCancelled { failure = .loadFailed }
        refresh()
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        failure = .processTerminated
        refresh()
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        // Frame-local blob/about documents are legitimate; never launch external schemes implicitly.
        if NavigationInput.isWebURL(url) || ["about", "blob"].contains(url.scheme ?? "") { return .allow }
        if navigationAction.targetFrame?.isMainFrame != false { failure = .unsupportedNavigation }
        return .cancel
    }

    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, NavigationInput.isWebURL(url) { onOpen?(url) }
        return nil
    }
}
