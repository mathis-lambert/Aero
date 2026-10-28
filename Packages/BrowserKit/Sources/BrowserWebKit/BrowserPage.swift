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

    public var webView: WKWebView { pageView }
    let pageView: PageWebView
    public private(set) var isLoading = false
    public private(set) var progress = 0.0
    public private(set) var canGoBack = false
    public private(set) var canGoForward = false
    public internal(set) var failure: PageFailure?
    /// The page and everything it loaded came over HTTPS with a certificate WebKit trusts.
    public private(set) var isSecure = false
    /// False until the first document has rendered a frame; later navigations keep it true.
    public private(set) var hasRenderedFirstFrame = false
    /// The address shown, once the page has one.
    public private(set) var url: URL?
    /// What it plays and records (docs/MEDIA.md).
    public internal(set) var activity = PageActivity()
    /// A two-finger swipe toward its history, while it shows (`PageSwipe`).
    public internal(set) var swipe: PageSwipe?
    @ObservationIgnored var swipeTracking: SwipeTracking?

    public enum PageFailure { case loadFailed, processTerminated, unsupportedNavigation }

    /// Set by the registry, which owns the tab identity behind each event.
    @ObservationIgnored var onMetadata: ((URL, String) -> Void)?
    /// The page started or finished loading.
    @ObservationIgnored var onLoadingChange: (() -> Void)?
    @ObservationIgnored var onActivity: ((PageActivity) -> Void)?
    /// Each frame's last media report, by the token its script drew (`MediaScripts`), and the frame the page's media is
    /// in, which the player's actions go to.
    @ObservationIgnored var mediaFrames: [String: MediaFrame] = [:]
    @ObservationIgnored var mediaFrameUpdates = 0
    @ObservationIgnored var mediaFrame: WKFrameInfo?
    @ObservationIgnored var onVisit: ((HistoryNavigation) -> Void)?
    @ObservationIgnored var onDownload: ((WKDownload) -> Void)?
    @ObservationIgnored var onIcons: (([FaviconLink], URL) -> Void)?
    @ObservationIgnored var onPopup: ((WKWebViewConfiguration, URL?, WKWindowFeatures) -> WKWebView?)?
    /// An address for another app, which the page does not load (docs/OTHER_APPS.md › Links to other apps).
    @ObservationIgnored var onApplicationLink: ((URL) -> Void)?
    /// The page's owner takes the addresses it returns `true` for instead of loading them, such as a sign-in's callback.
    @ObservationIgnored public var interceptsNavigation: ((URL) -> Bool)?
    @ObservationIgnored var onPageNavigation: ((URLRequest, URL?) -> Bool)?
    @ObservationIgnored var extensionOrigin: URL?
    @ObservationIgnored private let extensionReturn = ExtensionReturnNavigation()
    var navigationRevision: Int { extensionReturn.revision }
    /// The page called `window.close()`.
    @ObservationIgnored public var onClose: (() -> Void)?
    @ObservationIgnored var onPermission: ((SitePermission, SiteOrigin) -> SiteDecision?)?
    /// Asks the person what a page's `alert`, `confirm` or `prompt` asks.
    @ObservationIgnored public var onDialog: ((PageDialog) async -> PageDialogAnswer)?
    @ObservationIgnored private var dialogsShown = 0
    @ObservationIgnored private var dialogsSuppressed = false
    /// Reports of the page's sign-in and sign-up forms. See docs/PASSWORDS.md.
    @ObservationIgnored var onPasswordForm: ((PasswordFormEvent, PasswordFrame) -> Void)?
    /// What the person asks of a link's preview (docs/BROWSING.md › Peek).
    @ObservationIgnored var onPeek: ((PeekRequest) -> Void)?
    /// The context menu's item previewing a link; none without one.
    @ObservationIgnored var peekMenuTitle: String? {
        get { pageView.peekMenuTitle }
        set { pageView.peekMenuTitle = newValue }
    }
    /// The extensions' items for the context menu the page is opening.
    @ObservationIgnored var onContextMenu: (() -> [NSMenuItem])? {
        get { pageView.extensionMenuItems }
        set { pageView.extensionMenuItems = newValue }
    }
    @ObservationIgnored weak var contentBlocker: ContentBlocker?
    /// The blocker's state last applied, so a navigation that changes nothing sends WebKit nothing.
    @ObservationIgnored private var contentBlockingState: Int?
    /// Set while a video this page played went to picture in picture because its tab was left.
    @ObservationIgnored private var movedToPictureInPicture = false
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var requestedURL: URL?
    /// Suppresses repeated KVO updates of the same committed document.
    @ObservationIgnored private var visitedURL: URL?
    @ObservationIgnored var historyTransition = HistoryTransition.autoTopLevel
    @ObservationIgnored var historyReferrer: URL?
    @ObservationIgnored private var requestedHistoryTransition: HistoryTransition?
    @ObservationIgnored private var restoresHistory = false
    @ObservationIgnored private var firstFrameTimeout: Task<Void, Never>?
    @ObservationIgnored var documentGeneration = 0

    /// macOS WebKit turns picture in picture off in every web view and has no public setting for it;
    /// this is the private preference Safari sets. Without it, picture in picture is simply absent.
    private static let pictureInPictureSetter = NSSelectorFromString("_setAllowsPictureInPictureMediaPlayback:")

    private static func isPageURL(_ url: URL) -> Bool {
        NavigationInput.isWebURL(url) || NavigationInput.isExtensionURL(url) || NavigationInput.isLocalFileURL(url)
    }

    /// The profile's extensions are added by the registry's `PageExtensions`.
    static func configuration(store: WKWebsiteDataStore) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        configuration.applicationNameForUserAgent = BrowserIdentity.applicationNameForUserAgent
        configuration.preferences.isElementFullscreenEnabled = true
        PageRendering.configure(configuration.preferences)
        configuration.allowsAirPlayForMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = .audio
        if configuration.preferences.responds(to: pictureInPictureSetter) {
            configuration.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")
        }
        configuration.userContentController.addUserScript(PageScripts.editedFieldTracker)
        configuration.userContentController.addUserScript(PasswordScripts.forms)
        configuration.userContentController.add(PasswordFormBridge(), contentWorld: PageScripts.world, name: PasswordScripts.handlerName)
        configuration.userContentController.addUserScript(PeekScripts.linkFinder)
        configuration.userContentController.addUserScript(MediaScripts.session)
        configuration.userContentController.addUserScript(MediaScripts.elements)
        configuration.userContentController.add(MediaBridge(), contentWorld: PageScripts.world, name: MediaScripts.handlerName)
        return configuration
    }

    init(configuration: WKWebViewConfiguration) {
        pageView = PageWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        // Aero draws the swipe through history itself (`PageSwipe`), which WebKit's own would take.
        webView.allowsBackForwardNavigationGestures = false
        pageView.onScroll = { [weak self] event in self?.track(event) ?? false }
        pageView.onKey = { [weak self] event in self?.handleSwipeKey(event) ?? false }

        // Aero previews links itself (docs/BROWSING.md › Peek): WebKit's own preview would open beside it.
        webView.allowsLinkPreview = false
        pageView.onForcePress = { [weak self] press, point in self?.handle(press, at: point) }
        // WKWebView posts these on the main thread; applying them directly avoids a task per progress tick.
        let refresh: @Sendable (WKWebView, Any) -> Void = { [weak self] _, _ in MainActor.assumeIsolated { self?.refresh() } }
        observations = [
            webView.observe(\.estimatedProgress) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.progress = webView.estimatedProgress }
            },
            webView.observe(\.isLoading, changeHandler: refresh),
            webView.observe(\.canGoBack, changeHandler: refresh),
            webView.observe(\.canGoForward, changeHandler: refresh),
            webView.observe(\.title, changeHandler: refresh),
            webView.observe(\.url, changeHandler: refresh),
            webView.observe(\.hasOnlySecureContent, changeHandler: refresh)
        ] + observeCapture()
    }

    /// `headers` are sent with this request only, such as those a sign-in asks for.
    public func load(_ url: URL, headers: [String: String] = [:], transition: HistoryTransition = .typed) {
        var request = URLRequest(url: url)
        for (field, value) in headers { request.setValue(value, forHTTPHeaderField: field) }
        load(request, transition: transition)
    }

    func load(_ request: URLRequest, transition: HistoryTransition = .typed, referrer: URL? = nil) {
        guard let url = request.url, Self.isPageURL(url) else { fail(.unsupportedNavigation); return }
        failure = nil
        requestedURL = url
        requestedHistoryTransition = transition
        historyReferrer = referrer
        restoresHistory = false
        // A file reads only its own folder, never the rest of this Mac.
        if url.isFileURL { webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent()) }
        else { webView.load(request) }
    }

    /// Returns to a hibernated page's history and scroll position without an extra network request.
    func restore(_ interactionState: Any, sessionStorage: Data?, url: URL) {
        failure = nil
        requestedURL = url
        visitedURL = url
        restoresHistory = true
        guard let sessionStorage else { webView.interactionState = interactionState; return }
        // The document that loads back finds its storage.
        webView.restoreData(sessionStorage) { [weak self] _ in self?.webView.interactionState = interactionState }
    }

    public func reload() {
        failure = nil
        requestedHistoryTransition = .reload
        if webView.url != nil { webView.reload() }
        else if let requestedURL { load(requestedURL) }
    }
    public func stop() { webView.stopLoading() }
    public func goBack() { failure = nil; webView.goBack() }
    public func goForward() { failure = nil; webView.goForward() }

    /// Selects and scrolls to the next match, wrapping around; returns whether one exists.
    public func find(_ text: String, backwards: Bool) async -> Bool {
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

    public var serverTrust: SecTrust? { webView.serverTrust }

    // MARK: - Picture in picture

    /// Moves a playing video to picture in picture; a script from the app needs no click in the page.
    func moveVideoToPictureInPicture() async {
        let moved = try? await webView.callAsyncJavaScript(PageScripts.enterPictureInPicture, contentWorld: PageScripts.world)
        movedToPictureInPicture = moved as? Bool == true
    }

    /// Brings back inline the video `moveVideoToPictureInPicture` moved; one the user closed stays closed.
    func returnVideoFromPictureInPicture() {
        guard movedToPictureInPicture else { return }
        movedToPictureInPicture = false
        webView.callAsyncJavaScript(PageScripts.exitPictureInPicture, in: nil, in: PageScripts.world)
    }

    // MARK: - Content blocking

    /// Adds or removes the blocking rules for the site `url` belongs to; they apply from the next request.
    func updateContentBlocking(for url: URL? = nil) {
        guard let contentBlocker, let origin = (url ?? webView.url).flatMap(SiteOrigin.init(url:)) else { return }
        let enabled = onPermission?(.ads, origin) != .allow
        let state = contentBlocker.state(enabled: enabled)
        guard state != contentBlockingState else { return }
        contentBlockingState = state
        contentBlocker.apply(to: webView.configuration.userContentController, enabled: enabled)
    }

    func dispose() {
        documentGeneration += 1
        onMetadata = nil
        onLoadingChange = nil
        onActivity = nil
        dismissSwipe()
        pageView.onScroll = nil
        pageView.onKey = nil
        onVisit = nil
        onDownload = nil
        onIcons = nil
        onPopup = nil
        onDialog = nil
        onPermission = nil
        onApplicationLink = nil
        interceptsNavigation = nil
        onPageNavigation = nil
        onClose = nil
        onPasswordForm = nil
        onPeek = nil
        peekMenuTitle = nil
        onContextMenu = nil
        contentBlocker = nil
        firstFrameTimeout?.cancel()
        observations.removeAll()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
    }

    private func refresh() {
        let wasLoading = isLoading
        isLoading = webView.isLoading
        if isLoading != wasLoading { onLoadingChange?() }
        progress = webView.estimatedProgress
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isSecure = webView.url?.scheme == "https" && webView.hasOnlySecureContent
        url = webView.url
        guard let url = webView.url else { return }
        if NavigationInput.isExtensionURL(url) { onMetadata?(url, webView.title ?? ""); return }
        guard NavigationInput.isWebURL(url) else { return }
        // An address change outside a load is a same-document navigation (`pushState`).
        if !webView.isLoading { recordVisit(url, transition: .link, referrer: visitedURL) }
        onMetadata?(url, webView.title ?? "")
    }

    private func recordVisit(_ url: URL, transition: HistoryTransition, referrer: URL?, newDocument: Bool = false) {
        guard newDocument || url != visitedURL else { return }
        visitedURL = url
        onVisit?(HistoryNavigation(url: url, transition: transition, referrer: referrer, isWithinDocument: !newDocument))
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
        if let navigation { extensionReturn.started(navigation, at: webView.url) }
        documentGeneration += 1
        failure = nil
        refresh()
    }

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        awaitFirstFrame()
        resetMedia()
        resetDialogs()
        if restoresHistory { restoresHistory = false; return }
        if let url = webView.url, NavigationInput.isWebURL(url) {
            recordVisit(url, transition: historyTransition, referrer: historyReferrer, newDocument: true)
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        extensionReturn.finished(navigation)
        restoresHistory = false
        refresh()
        readDeclaredIcons()
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        extensionReturn.finished(navigation)
        if Self.isFailure(error) { fail(.loadFailed) }
        refresh()
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        extensionReturn.finished(navigation)
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
        if interceptsNavigation?(url) == true { return .cancel }
        let source = extensionReturn.source(for: navigationAction)
        if navigationAction.targetFrame?.isMainFrame == true {
            let requested = requestedHistoryTransition
            requestedHistoryTransition = nil
            switch navigationAction.navigationType {
            case .linkActivated: historyTransition = .link
            case .formSubmitted: historyTransition = .formSubmit
            case .formResubmitted: historyTransition = requested == .reload ? .reload : .formSubmit
            case .reload: historyTransition = .reload
            case .backForward: historyTransition = .autoTopLevel
            case .other: historyTransition = requested ?? .link
            @unknown default: historyTransition = .autoTopLevel
            }
            if requested == nil { historyReferrer = navigationAction.sourceFrame.request.url.flatMap { NavigationInput.isWebURL($0) ? $0 : nil } }
        }
        if navigationAction.targetFrame?.isMainFrame == true, onPageNavigation?(navigationAction.request, source) == true { return .cancel }
        if navigationAction.shouldPerformDownload { return .download }
        let isMainFrame = navigationAction.targetFrame?.isMainFrame != false
        // A file loads only when the person opened it, and from a file to the files of the folder it may read.
        if NavigationInput.isLocalFileURL(url), url == requestedURL || webView.url?.isFileURL == true { return .allow }
        switch NavigationInput.target(of: url) {
        case .page:
            if isMainFrame { updateContentBlocking(for: url) }
            return .allow
        case .application:
            // The page itself, or a link followed in one of its frames; a frame cannot launch apps on its own.
            if isMainFrame || navigationAction.navigationType == .linkActivated { onApplicationLink?(url) }
            return .cancel
        case .blocked:
            if isMainFrame { fail(.unsupportedNavigation) }
            return .cancel
        }
    }

    public func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        guard let navigation, let redirect = extensionReturn.redirected(navigation, to: webView.url),
              onPageNavigation?(redirect.request, redirect.source) == true else { return }
        webView.stopLoading()
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

    /// Popups may start blank (`about:blank`, then written by script) or at a website, never at another scheme,
    /// so a website cannot open a browser page such as `aero://history`. One for another app asks for that app.
    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = navigationAction.request.url, !url.absoluteString.isEmpty else { return onPopup?(configuration, nil, windowFeatures) }
        if interceptsNavigation?(url) == true { return nil }
        // The context menu's preview asked WebKit to open the link in a new window: it opens in the peek instead.
        if pageView.takePeekRequest() {
            if NavigationInput.isWebURL(url) { onPeek?(.open(url, nil)) }
            return nil
        }
        if NavigationInput.isWebURL(url) || url.scheme?.lowercased() == "about" { return onPopup?(configuration, url, windowFeatures) }
        if NavigationInput.target(of: url) == .application { onApplicationLink?(url) }
        return nil
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

// MARK: - Page dialogs and file choosers

extension BrowserPage {
    public func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        _ = await ask(.alert, message, from: frame)
    }

    public func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        await ask(.confirm, message, from: frame).accepted
    }

    public func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                        initiatedByFrame frame: WKFrameInfo) async -> String? {
        let answer = await ask(.prompt(defaultText: defaultText ?? ""), prompt, from: frame)
        return answer.accepted ? answer.text ?? "" : nil
    }

    /// A file input opens the system's open panel as a sheet on the page's window.
    public func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        guard let window = webView.window else { return nil }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        return await withCheckedContinuation { continuation in
            panel.beginSheetModal(for: window) { response in continuation.resume(returning: response == .OK ? panel.urls : nil) }
        }
    }

    private func ask(_ kind: PageDialog.Kind, _ message: String, from frame: WKFrameInfo) async -> PageDialogAnswer {
        guard !dialogsSuppressed, let onDialog else { return .dismissed }
        dialogsShown += 1
        let origin = frame.securityOrigin
        let site = origin.host.isEmpty ? (webView.url?.absoluteString ?? "") : origin.host
        let dialog = PageDialog(kind: kind, message: String(message.prefix(PageDialog.maximumLength)), site: site, offersSuppression: dialogsShown > 1)
        let answer = await onDialog(dialog)
        if answer.suppressesMore { dialogsSuppressed = true }
        return answer
    }

    /// A new document starts over: its dialogs show again.
    func resetDialogs() {
        dialogsShown = 0
        dialogsSuppressed = false
    }
}


/// A page's view: WebKit's, with the extensions' items added to its context menu, after WebKit's own, as Safari shows
/// them, and on a link an item previewing it.
final class PageWebView: WKWebView {
    var extensionMenuItems: (() -> [NSMenuItem])?
    var peekMenuTitle: String?
    var onForcePress: ((ForcePress, CGPoint) -> Void)?
    /// Every scroll event, for the swipe through history, before WebKit: answering true keeps it from the page.
    var onScroll: ((NSEvent) -> Bool)?
    /// A key the swipe's list takes before the page, answering whether it took it.
    var onKey: ((NSEvent) -> Bool)?
    /// Changes as each scroll gesture begins: the page's late answers about an earlier one are stale.
    private(set) var scrollGeneration = 0
    /// The press under way went deep, or became a force click.
    private var pressWentDeep = false
    private var pressForced = false
    /// Changes with each press, and as a deep press is released: the page's late answers about an earlier one are
    /// stale.
    private(set) var pressGeneration = 0
    /// Where a press starts a preview, past most clicks' pressure, on the way to a force click.
    private static let deepPressure: Float = 0.5
    /// The identifier WebKit gives its Open Link in New Window item. The SDK does not export it; should it change, the
    /// preview item is simply not offered.
    private static let openLinkInNewWindow = "WKMenuItemIdentifierOpenLinkInNewWindow"
    /// When the preview item ran WebKit's Open Link in New Window, whose new window the page asks for a moment later.
    private var peekRequested: ContinuousClock.Instant?
    /// Past this, a new window the page asks for is the page's own.
    private static let peekRequestLifetime = Duration.seconds(2)

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        if let peekMenuTitle, let open = menu.items.firstIndex(where: { $0.identifier?.rawValue == Self.openLinkInNewWindow }) {
            let item = NSMenuItem(title: peekMenuTitle, action: #selector(peekLink(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = menu.items[open]
            menu.insertItem(item, at: open + 1)
        }
        let items = extensionMenuItems?() ?? []
        guard !items.isEmpty else { return }
        menu.addItem(.separator())
        for item in items { menu.addItem(item) }
    }

    /// WebKit alone knows the link the menu is for: its own item opens it, and the page takes the new window it asks
    /// for as the preview's.
    @objc private func peekLink(_ sender: NSMenuItem) {
        guard let open = sender.representedObject as? NSMenuItem, let action = open.action else { return }
        peekRequested = .now
        NSApp.sendAction(action, to: open.target, from: open)
    }

    /// Whether the new window the page asks for is the preview's; asking answers once.
    func takePeekRequest() -> Bool {
        defer { peekRequested = nil }
        return peekRequested.map { .now - $0 < Self.peekRequestLifetime } ?? false
    }

    override func scrollWheel(with event: NSEvent) {
        if event.phase.contains(.began) { scrollGeneration += 1 }
        if onScroll?(event) == true { return }
        super.scrollWheel(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if onKey?(event) == true { return }
        super.keyDown(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        pressWentDeep = false
        pressForced = false
        pressGeneration += 1
        super.mouseDown(with: event)
    }

    override func pressureChange(with event: NSEvent) {
        super.pressureChange(with: event)
        guard let onForcePress, !pressForced else { return }
        if event.stage >= 2 {
            pressForced = true
            onForcePress(.forceClick, pagePoint(of: event))
        } else if event.stage == 1, event.pressure >= Self.deepPressure {
            if !pressWentDeep {
                pressWentDeep = true
                onForcePress(.deep, pagePoint(of: event))
            }
            onForcePress(.pressure(Double((event.pressure - Self.deepPressure) / (1 - Self.deepPressure))), .zero)
        } else if event.stage == 1, pressWentDeep {
            onForcePress(.pressure(0), .zero)
        }
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        endPress()
    }

    /// A deep press that moves drags its link: the press ends there, as the drag, not the view, receives the release.
    override func beginDraggingSession(with items: [NSDraggingItem], event: NSEvent, source: any NSDraggingSource) -> NSDraggingSession {
        endPress()
        return super.beginDraggingSession(with: items, event: event, source: source)
    }

    private func endPress() {
        if pressWentDeep, !pressForced {
            pressGeneration += 1
            onForcePress?(.released, .zero)
        }
        pressWentDeep = false
        pressForced = false
    }

    /// The event's place from the view's top left, as the page measures it.
    func pagePoint(of event: NSEvent) -> CGPoint {
        let point = convert(event.locationInWindow, from: nil)
        return CGPoint(x: point.x, y: isFlipped ? point.y : bounds.height - point.y)
    }
}

extension BrowserPage {
    /// A rectangle a page script measured, in CSS pixels of the viewport, in the web view's points.
    func viewRect(fromPage value: Any?) -> CGRect? {
        guard let rect = value as? [String: Any], let x = rect["x"] as? Double, let y = rect["y"] as? Double,
              let width = rect["width"] as? Double, let height = rect["height"] as? Double,
              [x, y, width, height].allSatisfy(\.isFinite), width > 0, height > 0 else { return nil }
        let scale = webView.pageZoom * webView.magnification
        return CGRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
    }
}
