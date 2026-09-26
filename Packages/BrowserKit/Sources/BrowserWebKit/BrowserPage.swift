import BrowserCore
import Foundation
import Observation
import WebKit

@MainActor @Observable
public final class BrowserPage: NSObject, WKNavigationDelegate, WKUIDelegate {
    static let firstFrameTimeout = Duration.milliseconds(1500)
    /// WebKit reports a navigation that became a download with this domain and code; the current
    /// page stays as it was.
    private static let webKitErrorDomain = "WebKitErrorDomain"
    private static let frameLoadInterruptedByPolicyChange = 102

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
    @ObservationIgnored var onVisit: ((URL) -> Void)?
    @ObservationIgnored var onDownload: ((WKDownload) -> Void)?
    @ObservationIgnored var onIcons: (([FaviconLink], URL) -> Void)?
    @ObservationIgnored var onPopup: ((WKWebViewConfiguration, URL?) -> WKWebView?)?
    @ObservationIgnored var onClose: (() -> Void)?
    @ObservationIgnored var onPermission: ((SitePermission, SiteOrigin) -> SiteDecision?)?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var requestedURL: URL?
    /// The address of the last recorded visit; reloads and restores of it add no visit.
    @ObservationIgnored private var visitedURL: URL?
    @ObservationIgnored private var firstFrameTimeout: Task<Void, Never>?

    /// Safari's user agent suffix. Without it, sites such as Google see an unknown WebKit browser and
    /// serve their basic, legacy pages. The installed Safari's version matches the system's engine.
    static let userAgentName = "Version/\(safariVersion) Safari/605.1.15"

    private static var safariVersion: String {
        ["/System/Cryptexes/App/System/Applications/Safari.app", "/Applications/Safari.app"].lazy
            .compactMap { Bundle(path: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String }
            .first ?? "27.0"
    }

    static func configuration(store: WKWebsiteDataStore) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        configuration.applicationNameForUserAgent = userAgentName
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
        // WKWebView posts these on the main thread; applying them directly avoids a task per progress tick.
        let refresh: @Sendable (WKWebView, Any) -> Void = { [weak self] _, _ in MainActor.assumeIsolated { self?.refresh() } }
        observations = [
            webView.observe(\.estimatedProgress, changeHandler: refresh),
            webView.observe(\.isLoading, changeHandler: refresh),
            webView.observe(\.canGoBack, changeHandler: refresh),
            webView.observe(\.canGoForward, changeHandler: refresh),
            webView.observe(\.title, changeHandler: refresh),
            webView.observe(\.url, changeHandler: refresh)
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
        visitedURL = url
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

    /// Selects and scrolls to the next match, wrapping around; returns whether one exists.
    public func find(_ text: String, backwards: Bool = false) async -> Bool {
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        return (try? await webView.find(text, configuration: configuration))?.matchFound == true
    }

    /// The page's selected text, bounded, to prefill searches.
    public func selectedText() async -> String? {
        let result = try? await webView.callAsyncJavaScript(PageScripts.selectedText, contentWorld: PageScripts.world)
        guard let text = result as? String, !text.isEmpty else { return nil }
        return text
    }

    public func focus() { webView.window?.makeFirstResponder(webView) }

    func dispose() {
        onMetadata = nil
        onVisit = nil
        onDownload = nil
        onIcons = nil
        onPopup = nil
        onClose = nil
        onPermission = nil
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
        guard let url = webView.url, NavigationInput.isWebURL(url) else { return }
        // An address change outside a load is a same-document navigation (`pushState`).
        if !webView.isLoading { recordVisit(url) }
        onMetadata?(url, webView.title ?? "")
    }

    private func recordVisit(_ url: URL) {
        guard url != visitedURL else { return }
        visitedURL = url
        onVisit?(url)
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
        // Either outcome reveals the page: a script failure must not leave it hidden. The handler holds
        // no reference to the view, so a page closed before painting is released with its pending script.
        webView.callAsyncJavaScript(PageScripts.nextFrame, in: nil, in: PageScripts.world) { [weak self] _ in
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

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        awaitFirstFrame()
        if let url = webView.url, NavigationInput.isWebURL(url) { recordVisit(url) }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refresh()
        readDeclaredIcons()
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        if Self.isFailure(error) { fail(.loadFailed) }
        refresh()
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        if Self.isFailure(error) { fail(.loadFailed) }
        refresh()
    }

    /// Cancelled loads and navigations that became downloads are not failures of the page.
    private static func isFailure(_ error: any Error) -> Bool {
        let error = error as NSError
        if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled { return false }
        return !(error.domain == webKitErrorDomain && error.code == frameLoadInterruptedByPolicyChange)
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        fail(.processTerminated)
        refresh()
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .cancel }
        if navigationAction.shouldPerformDownload { return .download }
        // Frame-local blob/about documents are legitimate; never launch external schemes implicitly.
        if NavigationInput.isWebURL(url) || ["about", "blob"].contains(url.scheme ?? "") { return .allow }
        if navigationAction.targetFrame?.isMainFrame != false { fail(.unsupportedNavigation) }
        return .cancel
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition")
        let isAttachment = disposition?.lowercased().hasPrefix("attachment") == true
        return isAttachment || !navigationResponse.canShowMIMEType ? .download : .allow
    }

    public func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        onDownload?(download)
    }

    public func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        onDownload?(download)
    }

    // MARK: - WKUIDelegate

    /// Popups may start blank (`about:blank`, then written by script) but never at another scheme,
    /// so a website cannot open a browser page such as `aero://history`.
    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let url = navigationAction.request.url
        if let url, !url.absoluteString.isEmpty, !NavigationInput.isWebURL(url), url.scheme != "about" { return nil }
        return onPopup?(configuration, url)
    }

    public func webViewDidClose(_ webView: WKWebView) { onClose?() }

    public func webView(_ webView: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin, initiatedBy frame: WKFrameInfo, type: WKMediaCaptureType) async -> WKPermissionDecision {
        switch type {
        case .camera: decision(for: [.camera], requestedBy: origin)
        case .microphone: decision(for: [.microphone], requestedBy: origin)
        case .cameraAndMicrophone: decision(for: [.camera, .microphone], requestedBy: origin)
        @unknown default: .prompt
        }
    }

    public func webView(_ webView: WKWebView, requestGeolocationPermissionFor origin: WKSecurityOrigin, initiatedBy frame: WKFrameInfo) async -> WKPermissionDecision {
        decision(for: [.location], requestedBy: origin)
    }

    /// The page's origin decides, including for the frames it delegates to; one blocked permission
    /// refuses the request, and anything short of all allowed leaves WebKit to prompt.
    private func decision(for permissions: [SitePermission], requestedBy origin: WKSecurityOrigin) -> WKPermissionDecision {
        guard let site = webView.url.flatMap(SiteOrigin.init(url:)) ?? SiteOrigin(scheme: origin.protocol, host: origin.host, port: origin.port),
              let onPermission else { return .prompt }
        let decisions = permissions.map { onPermission($0, site) }
        if decisions.contains(.block) { return .deny }
        return decisions.allSatisfy { $0 == .allow } ? .grant : .prompt
    }
}
