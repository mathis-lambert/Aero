import AuthenticationServices
import Foundation
import Observation
import Security

/// App-wide browser consent, independent of profile passwords and WebKit's credential ceremonies.
@MainActor @Observable
final class PasskeyAccess {
    typealias AuthorizationState = ASAuthorizationWebBrowserPublicKeyCredentialManager.AuthorizationState

    let isSupported: Bool
    private(set) var state: AuthorizationState?
    private(set) var isRequesting = false
    @ObservationIgnored private var attemptedAutomatically = false
    @ObservationIgnored private let authorizationState: @MainActor () -> AuthorizationState
    @ObservationIgnored private let request: @MainActor () async -> Void

    convenience init() {
        let manager = ASAuthorizationWebBrowserPublicKeyCredentialManager()
        self.init(isSupported: ProcessInfo.processInfo.environment["AERO_TEST_DATA"] == nil
                  && Self.hasBrowserEntitlement(), authorizationState: {
            manager.authorizationStateForPlatformCredentials
        }, request: {
            _ = await manager.requestAuthorizationForPublicKeyCredentials()
        })
    }

    init(isSupported: Bool, authorizationState: @escaping @MainActor () -> AuthorizationState,
         request: @escaping @MainActor () async -> Void) {
        self.isSupported = isSupported
        self.authorizationState = authorizationState
        self.request = request
        refresh()
    }

    func refresh() {
        state = isSupported ? authorizationState() : nil
    }

    /// Called only with a ready, foreground browser, after onboarding. Never blocks website requests.
    func prepareForBrowsing() async {
        refresh()
        guard !attemptedAutomatically, state == .notDetermined, !Task.isCancelled else { return }
        attemptedAutomatically = true
        await requestAccess()
    }

    func requestAccess() async {
        refresh()
        guard state == .notDetermined, !isRequesting, !Task.isCancelled else { return }
        isRequesting = true
        // The system owns this prompt. Cancellation must not free the slot before its callback completes.
        await request()
        refresh()
        isRequesting = false
    }

    private static func hasBrowserEntitlement() -> Bool {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var information: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation),
                                           &information) == errSecSuccess,
              let details = information as? [String: Any],
              let entitlements = details[kSecCodeInfoEntitlementsDict as String] as? [String: Any]
        else { return false } // Source/ad-hoc builds cannot request this managed permission.
        return entitlements["com.apple.developer.web-browser.public-key-credential"] as? Bool == true
    }
}
