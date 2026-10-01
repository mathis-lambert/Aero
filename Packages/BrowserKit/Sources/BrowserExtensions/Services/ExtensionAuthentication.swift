import AppKit
import Foundation
import WebKit

/// One web authorization request. Only this view's main-frame navigation can finish its flow.
@MainActor
final class ExtensionAuthentication: NSObject, WKNavigationDelegate, WKUIDelegate, NSWindowDelegate {
    enum Failure: LocalizedError {
        case interactionRequired, closed, timedOut, noBrowserAccount
        var errorDescription: String? {
            switch self {
            case .interactionRequired: "Authorization requires user interaction."
            case .closed: "The authorization window was closed."
            case .timedOut: "Authorization timed out."
            case .noBrowserAccount: "No browser account is signed in. Use launchWebAuthFlow for web authorization."
            }
        }
    }

    struct Options {
        let url: URL
        let interactive: Bool
        let abortOnLoad: Bool
        let timeout: Duration

        init(_ body: [String: Any]) throws {
            guard let text = body["url"] as? String, let url = URL(string: text),
                  ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host() != nil,
                  url.user == nil, url.password == nil else { throw ExtensionBridge.Failure.invalidRequest }
            if let timeout = body["timeoutMsForNonInteractive"] {
                guard let number = timeout as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { throw ExtensionBridge.Failure.invalidRequest }
            }
            for key in ["interactive", "abortOnLoadForNonInteractive"] {
                if let value = body[key] {
                    guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else { throw ExtensionBridge.Failure.invalidRequest }
                }
            }
            let milliseconds = (body["timeoutMsForNonInteractive"] as? NSNumber)?.doubleValue ?? 10_000
            guard milliseconds.isFinite, milliseconds > 0 else { throw ExtensionBridge.Failure.invalidRequest }
            self.url = url
            interactive = body["interactive"] as? Bool ?? false
            abortOnLoad = body["abortOnLoadForNonInteractive"] as? Bool ?? true
            timeout = .milliseconds(milliseconds)
        }
    }

    let webView: WKWebView
    private let window: NSWindow
    private let identifier: String
    private let options: Options
    private var continuation: CheckedContinuation<String, any Error>?
    private var timeoutTask: Task<Void, Never>?
    private var providerWindows: [WKWebView: NSWindow] = [:]

    init(identifier: String, options: Options, configuration: WKWebViewConfiguration, title: String) {
        self.identifier = identifier
        self.options = options
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 720), configuration: configuration)
        window = NSWindow(contentRect: webView.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.title = title
        window.contentView = webView
        window.delegate = self
        window.center()
        webView.navigationDelegate = self
        webView.uiDelegate = self
    }

    isolated deinit {
        timeoutTask?.cancel()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        window.delegate = nil
        window.close()
        for (view, window) in providerWindows {
            view.stopLoading()
            view.navigationDelegate = nil
            view.uiDelegate = nil
            window.delegate = nil
            window.close()
        }
    }

    func run() async throws -> String {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                if !options.interactive {
                    timeoutTask = Task { [weak self, timeout = options.timeout] in
                        do { try await Task.sleep(for: timeout) } catch { return }
                        self?.finish(.failure(Failure.timedOut))
                    }
                }
                webView.load(URLRequest(url: options.url))
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    static func isRedirect(_ url: URL, for identifier: String) -> Bool {
        url.scheme?.lowercased() == "https" && url.host()?.lowercased() == identifier.lowercased() + ".chromiumapp.org"
            && url.user == nil && url.password == nil && (url.port == nil || url.port == 443)
    }

    func cancel() { finish(.failure(CancellationError())) }
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === window { finish(.failure(Failure.closed)) }
        else if let view = providerWindows.first(where: { $0.value === notification.object as? NSWindow })?.key { closeProvider(view) }
    }
    func webViewDidClose(_ webView: WKWebView) {
        if webView === self.webView { finish(.failure(Failure.closed)) }
        else { closeProvider(webView) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard navigationAction.targetFrame?.isMainFrame == true, let url = navigationAction.request.url else { return .allow }
        if Self.isRedirect(url, for: identifier) {
            finish(.success(url.absoluteString))
            return .cancel
        }
        return ["http", "https", "about"].contains(url.scheme?.lowercased() ?? "") ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard continuation != nil else { return }
        if options.interactive { (webView === self.webView ? window : providerWindows[webView])?.makeKeyAndOrderFront(nil) }
        else if options.abortOnLoad, webView === self.webView { finish(.failure(Failure.interactionRequired)) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { finish(.failure(error)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { finish(.failure(error)) }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard continuation != nil, let url = action.request.url,
              ["http", "https", "about"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        if Self.isRedirect(url, for: identifier) { finish(.success(url.absoluteString)); return nil }
        // WebKit's supplied configuration preserves the provider's native window.opener.
        let view = WKWebView(frame: self.webView.frame, configuration: configuration)
        let provider = NSWindow(contentRect: view.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        provider.isReleasedWhenClosed = false
        provider.title = window.title
        provider.contentView = view
        provider.delegate = self
        provider.center()
        view.navigationDelegate = self
        view.uiDelegate = self
        providerWindows[view] = provider
        return view
    }

    private func closeProvider(_ view: WKWebView) {
        guard let window = providerWindows.removeValue(forKey: view) else { return }
        view.stopLoading()
        view.navigationDelegate = nil
        view.uiDelegate = nil
        window.delegate = nil
        window.close()
    }

    private func finish(_ result: Result<String, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel(); timeoutTask = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        window.delegate = nil
        window.close()
        for view in Array(providerWindows.keys) { closeProvider(view) }
        continuation.resume(with: result)
    }
}

extension ProfileExtensions {
    /// Web authorization only: Aero has no browser account, so account and token requests say so.
    func identityRequest(_ action: String, _ body: [String: Any], context: WKWebExtensionContext) async throws -> Any? {
        let extensionID = context.uniqueIdentifier
        try require("identity", of: extensionID)
        switch action {
        case "launch":
            guard let configuration = host?.websiteConfiguration(forProfile: profileID) else { throw CancellationError() }
            let flow = try ExtensionAuthentication(identifier: extensionID, options: .init(body), configuration: configuration,
                                                   title: context.webExtension.displayName ?? extensionID)
            let id = UUID()
            authentication[extensionID, default: [:]][id] = flow
            defer { authentication[extensionID]?[id] = nil }
            return try await flow.run()
        case "profile": return ["email": "", "id": ""]
        case "accounts": return [Any]()
        case "token": throw ExtensionAuthentication.Failure.noBrowserAccount
        case "removeToken", "clearTokens": return nil
        default: throw ExtensionBridge.Failure.unknownRequest
        }
    }

    func cancelAuthentication(of extensionID: String) {
        for flow in authentication.removeValue(forKey: extensionID)?.values.map({ $0 }) ?? [] { flow.cancel() }
    }
}
