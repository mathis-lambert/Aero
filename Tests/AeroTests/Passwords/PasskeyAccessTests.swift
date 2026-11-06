import AuthenticationServices
import Testing
@testable import Aero

// Failure modes: unentitled builds prompt; repeated activation prompts again; concurrent requests overlap;
// denial is ignored; returning from System Settings leaves stale state.
@MainActor
struct PasskeyAccessTests {
    @MainActor private final class Provider {
        var state = ASAuthorizationWebBrowserPublicKeyCredentialManager.AuthorizationState.notDetermined
        var requests = 0
        var continuation: CheckedContinuation<Void, Never>?
        var waits = false

        func makeAccess(supported: Bool = true) -> PasskeyAccess {
            PasskeyAccess(isSupported: supported, authorizationState: { self.state }, request: {
                self.requests += 1
                if self.waits { await withCheckedContinuation { self.continuation = $0 } }
                self.state = .authorized
            })
        }
    }

    @Test func unentitledBuildDoesNotRequestAccess() async {
        let provider = Provider()
        let access = provider.makeAccess(supported: false)
        await access.prepareForBrowsing()
        await access.requestAccess()
        #expect(provider.requests == 0)
        #expect(access.state == nil)
    }

    @Test func foregroundPreparationRequestsOnlyOnce() async {
        let provider = Provider()
        let access = provider.makeAccess()
        await access.prepareForBrowsing()
        provider.state = .notDetermined
        await access.prepareForBrowsing()
        #expect(provider.requests == 1)
    }

    @Test func denialIsRespectedAndExternalChangesAreRefreshed() async {
        let provider = Provider()
        provider.state = .denied
        let access = provider.makeAccess()
        await access.prepareForBrowsing()
        await access.requestAccess()
        #expect(provider.requests == 0)
        #expect(access.state == .denied)
        provider.state = .authorized
        access.refresh()
        #expect(access.state == .authorized)
        provider.state = .denied
        access.refresh()
        #expect(access.state == .denied)
    }

    @Test func overlappingRequestsShareTheSystemPrompt() async {
        let provider = Provider()
        provider.waits = true
        let access = provider.makeAccess()
        let first = Task { await access.prepareForBrowsing() }
        while provider.continuation == nil { await Task.yield() }
        #expect(access.isRequesting)
        first.cancel() // The system callback still owns the outstanding request.
        await access.requestAccess()
        await access.prepareForBrowsing()
        #expect(provider.requests == 1)
        provider.continuation?.resume()
        await first.value
        #expect(!access.isRequesting)
        #expect(access.state == .authorized)
    }
}
