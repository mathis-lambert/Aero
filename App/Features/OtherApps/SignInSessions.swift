import AppKit
import AuthenticationServices
import BrowserCore
import BrowserWebKit
import os
import SwiftUI

/// Other apps' sign-ins, which macOS hands to the default browser through `ASWebAuthenticationSession`. Each runs
/// in a window of its own until its service redirects to the app's callback, the person cancels, or the app gives up.
/// See docs/OTHER_APPS.md › Sign-in for other apps.
@MainActor
final class SignInSessions: NSObject {
    private static let logger = Logger(subsystem: Diagnostics.subsystem, category: "OtherApps")

    weak var browser: BrowserModel?
    /// Requests that arrived before records were loaded: they need the profile's website data.
    private var waiting: [ASWebAuthenticationSessionRequest] = []
    private var sessions: [UUID: SignInSession] = [:]

    /// AuthenticationServices keeps the handler. Registered at launch, so a launch for a sign-in receives it.
    func register() { ASWebAuthenticationSessionWebBrowserSessionManager.shared.sessionHandler = self }

    /// macOS started Aero only to sign in: the main window stays closed until the person asks for it.
    static var wasLaunchedForSignIn: Bool {
        ASWebAuthenticationSessionWebBrowserSessionManager.shared.wasLaunchedByAuthenticationServices
    }

    func beginPending() {
        let requests = waiting
        waiting = []
        requests.forEach(start)
    }

    /// A private sign-in uses no existing website data and keeps none; any other signs in with the selected space's
    /// profile, so an account already signed in there is reused.
    private func start(_ request: ASWebAuthenticationSessionRequest) {
        guard sessions[request.uuid] == nil, !waiting.contains(where: { $0.uuid == request.uuid }) else { return }
        guard let browser, browser.isReady, let profileID = browser.profile?.id ?? browser.session.profiles.first?.id else {
            waiting.append(request)
            return
        }
        let id = request.uuid
        let page = browser.pages.makeSignInPage(profileID: profileID, isPrivate: request.shouldUseEphemeralSession)
        let session = SignInSession(request: request, page: page) { [weak self] in self?.remove(id) }
        sessions[id] = session
        session.show()
    }

    private func stop(_ request: ASWebAuthenticationSessionRequest) {
        waiting.removeAll { $0.uuid == request.uuid }
        sessions[request.uuid]?.end(reporting: nil)
    }

    private func remove(_ id: UUID) {
        guard let session = sessions.removeValue(forKey: id) else { return }
        browser?.pages.discardDetachedPage(session.page)
    }
}

extension SignInSessions: ASWebAuthenticationSessionWebBrowserSessionHandling {
    // AuthenticationServices does not document the calling queue. Each request is handed over once, here, and used
    // only on the main actor afterwards, so it never crosses concurrently.
    nonisolated func begin(_ request: ASWebAuthenticationSessionRequest) {
        nonisolated(unsafe) let request = request
        Task { @MainActor in self.start(request) }
    }

    nonisolated func cancel(_ request: ASWebAuthenticationSessionRequest) {
        nonisolated(unsafe) let request = request
        Task { @MainActor in self.stop(request) }
    }
}

/// One sign-in: its request, its page and its window, which end together.
@MainActor
final class SignInSession: NSObject, NSWindowDelegate {
    enum Report { case callback(URL), cancelled }

    let request: ASWebAuthenticationSessionRequest
    let page: BrowserPage
    private let onEnd: () -> Void
    private var window: NSWindow?
    private var hasEnded = false

    init(request: ASWebAuthenticationSessionRequest, page: BrowserPage, onEnd: @escaping () -> Void) {
        self.request = request
        self.page = page
        self.onEnd = onEnd
        super.init()
        // The callback is the service's answer for the app: it is returned, never loaded or offered to another app.
        page.interceptsNavigation = { [weak self] url in
            guard let self, !hasEnded, request.callback?.matchesURL(url) == true else { return false }
            // After WebKit's policy decision returns: ending closes the page that is asking.
            Task { self.end(reporting: .callback(url)) }
            return true
        }
        page.load(request.url, headers: request.additionalHeaderFields ?? [:])
    }

    func show() {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: CGSize(width: 520, height: 700)),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = String(localized: "Sign In")
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentMinSize = CGSize(width: 400, height: 480)
        window.contentView = NSHostingView(rootView: SignInView(page: page, isPrivate: request.shouldUseEphemeralSession) { [weak self] in
            self?.end(reporting: .cancelled)
        })
        window.delegate = self
        window.center()
        self.window = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// `nil` when the calling app ended the request itself, which then expects no answer.
    func end(reporting report: Report?) {
        guard !hasEnded else { return }
        hasEnded = true
        switch report {
        case .callback(let url): request.complete(withCallbackURL: url)
        case .cancelled: request.cancelWithError(ASWebAuthenticationSessionError(.canceledLogin))
        case nil: break
        }
        window?.delegate = nil
        window?.close()
        window = nil
        onEnd()
    }

    func windowWillClose(_ notification: Notification) { end(reporting: .cancelled) }
}

/// The site being signed in to, how private the sign-in is, and the page itself.
private struct SignInView: View {
    let page: BrowserPage
    let isPrivate: Bool
    let cancel: () -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        SiteWindowContent(page: page) {
            if isPrivate {
                Text("Private sign-in")
                    .font(.caption)
                    .foregroundStyle(palette.secondary)
                    .tooltip(Text("This sign-in uses no saved website data and keeps none."))
            }
            Spacer(minLength: 8)
            Button("Cancel", action: cancel)
                .keyboardShortcut(.cancelAction)
                .accessibilityIdentifier("signIn.cancel")
        }
        .accessibilityIdentifier("signIn")
    }
}
