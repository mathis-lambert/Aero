// Adapted from the Search browser's passkeys (Passkeys.swift and its page scripts):
//
// Copyright (c) 2026 Office Commun
//
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
// associated documentation files (the "Software"), to deal in the Software without restriction,
// including without limitation the rights to use, copy, modify, merge, publish, distribute,
// sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all copies or
// substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
// NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
// DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT
// OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

import AppKit
import AuthenticationServices
import BrowserCore
import Security
import WebKit

/// Passkeys through AuthenticationServices, for a browser that is not Safari. See docs/PASSWORDS.md › Passkeys.
///
/// Left to WebKit, a page waiting on conditional mediation holds an AutoFill operation with the
/// system's authentication agent; if the app ends meanwhile, the agent refuses every later request
/// until the Mac restarts. So Aero carries the ceremony itself, as Chrome and Firefox do: the page's
/// request comes through Aero's world, is checked against the frame WebKit reports, and goes to
/// AuthenticationServices with client data Aero writes. Conditional requests wait and never reach macOS.
@MainActor
public final class PasskeyCeremony: NSObject {
    static let entitlement = "com.apple.developer.web-browser.public-key-credential"

    /// Whether this build may use passkeys: the entitlement is granted by Apple to browsers and needs a
    /// provisioning profile, which source builds do not have.
    public static let isAvailable: Bool = {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, entitlement as CFString, nil) as? Bool == true
    }()

    /// Decides which relying party a page may name: its host, or a domain above it that is not a public suffix.
    public var suffixes: PublicSuffixList?

    private var controller: ASAuthorizationController?
    private var token: String?
    private var answer: (([String: Any]) -> Void)?
    private weak var anchor: NSWindow?
    /// Requests aborted while macOS is asking for access.
    private var withdrawn: Set<String> = []
    private var pendingTokens: Set<String> = []
    /// Everyone waiting on macOS's one-time question about the Mac's passkeys.
    private var waiting: [() -> Void]?

    /// Where a request came from, as WebKit knows it.
    struct Caller {
        let origin: WKSecurityOrigin
        let pageOrigin: SiteOrigin?
        let window: NSWindow?
    }

    func cancel(token: String?) {
        guard let token, token.utf8.count <= 128 else { return }
        if token == self.token { controller?.cancel() }
        else if pendingTokens.contains(token) { withdrawn.insert(token) }
    }

    func perform(_ body: [String: Any], from caller: Caller, isCurrent: @escaping @MainActor () -> Bool,
                 answer: @escaping ([String: Any]) -> Void) {
        let kind = body["kind"] as? String ?? ""
        let descriptorValue = kind == "create" ? body["excludeCredentials"] : body["allowCredentials"]
        let descriptors = descriptorValue as? [[String: Any]] ?? []
        guard (descriptorValue == nil || descriptorValue is [[String: Any]]), descriptors.count <= 128,
              descriptors.allSatisfy({ item in
                  let transports = item["transports"] as? [String] ?? []
                  return Self.data(item["id"]) != nil && transports.count <= 8
                      && transports.allSatisfy { $0.utf8.count <= 32 }
              }), ((body["algorithms"] as? [Int])?.count ?? 0) <= 32 else {
            return answer(Self.failure("TypeError", "Invalid credential descriptors."))
        }
        let scheme = caller.origin.protocol.lowercased()
        let host = caller.origin.host.lowercased()
        let local = host == "localhost" || host.hasSuffix(".localhost") || host == "127.0.0.1" || host == "::1"
        guard !host.isEmpty, scheme == "https" || (scheme == "http" && local) else {
            return answer(Self.failure("NotAllowedError", "Passkeys need a secure page."))
        }
        // Only the page in front: a background tab or window does not bring up the sheet.
        guard NSApp.isActive, caller.window?.isKeyWindow == true, isCurrent() else {
            return answer(Self.failure("NotAllowedError", "The document is not focused."))
        }
        let frameOrigin = SiteOrigin(scheme: scheme, host: host, port: caller.origin.port)
        guard caller.pageOrigin == frameOrigin else {
            return answer(Self.failure("NotAllowedError", "Passkeys can't be asked for from another site's frame."))
        }
        let named = kind == "create" ? (body["rp"] as? [String: Any])?["id"] as? String : body["rpId"] as? String
        let rp = (named.flatMap { $0.isEmpty ? nil : $0 } ?? host).lowercased()
        guard rp.utf8.count <= 253, fits(rp, host) else {
            return answer(Self.failure("SecurityError", "The relying party ID is not a registrable domain suffix of, nor equal to the current domain."))
        }
        guard let challenge = Self.data(body["challenge"]), !challenge.isEmpty else {
            return answer(Self.failure("TypeError", "A challenge is required."))
        }
        let port = caller.origin.port
        let origin = "\(scheme)://\(host.contains(":") ? "[\(host)]" : host)" + (port == 0 ? "" : ":\(port)")
        let clientData = ASPublicKeyCredentialClientData(challenge: challenge, origin: origin)
        let requests: [ASAuthorizationRequest]
        switch kind {
        case "get":
            requests = assertion(body, rp: rp, clientData: clientData)
        case "create":
            guard let made = registration(body, rp: rp, clientData: clientData) else {
                return answer(Self.failure("TypeError", "The request names no user, or one too long."))
            }
            requests = made
        default:
            return answer(Self.failure("NotSupportedError", "Not a passkey request."))
        }
        guard !requests.isEmpty else {
            return answer(Self.failure("NotSupportedError", "No authenticator here can make that kind of key."))
        }
        guard let token = body["token"] as? String, !token.isEmpty, token.utf8.count <= 128,
              pendingTokens.count < 32, !pendingTokens.contains(token) else {
            return answer(Self.failure("TypeError", "Invalid request token."))
        }
        pendingTokens.insert(token)
        ensureAccess { [weak self] in
            guard let self else { return }
            self.pendingTokens.remove(token)
            if self.withdrawn.remove(token) != nil {
                return answer(Self.failure("AbortError", "The operation was aborted."))
            }
            guard NSApp.isActive, caller.window?.isKeyWindow == true, isCurrent() else {
                return answer(Self.failure("AbortError", "The page changed before the operation began."))
            }
            self.begin(requests, token: token, in: caller.window, answer: answer)
        }
    }

    /// macOS asks once whether Aero may use the Mac's passkeys; asked when a site first wants one.
    private func ensureAccess(_ then: @escaping () -> Void) {
        let manager = ASAuthorizationWebBrowserPublicKeyCredentialManager()
        guard manager.authorizationStateForPlatformCredentials == .notDetermined else { return then() }
        if waiting != nil { waiting?.append(then); return }
        waiting = [then]
        manager.requestAuthorizationForPublicKeyCredentials { [weak self] _ in
            Task { @MainActor in
                let everyone = self?.waiting ?? []
                self?.waiting = nil
                everyone.forEach { $0() }
            }
        }
    }

    private func begin(_ requests: [ASAuthorizationRequest], token: String?, in window: NSWindow?, answer: @escaping ([String: Any]) -> Void) {
        if let running = controller {
            let previous = self.answer
            clear()
            running.cancel()
            previous?(Self.failure("NotAllowedError", "A newer request took its place."))
        }
        let controller = ASAuthorizationController(authorizationRequests: requests)
        controller.delegate = self
        controller.presentationContextProvider = self
        self.controller = controller
        self.token = token
        self.answer = answer
        anchor = window
        controller.performRequests()
    }

    // MARK: - Requests

    private func assertion(_ body: [String: Any], rp: String, clientData: ASPublicKeyCredentialClientData) -> [ASAuthorizationRequest] {
        let allowed = Self.descriptors(body["allowCredentials"])
        let verification = Self.verification(body["userVerification"])
        let platform = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rp).createCredentialAssertionRequest(clientData: clientData)
        platform.allowedCredentials = allowed.map { ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0.id) }
        platform.userVerificationPreference = verification
        let key = ASAuthorizationSecurityKeyPublicKeyCredentialProvider(relyingPartyIdentifier: rp).createCredentialAssertionRequest(clientData: clientData)
        key.allowedCredentials = allowed.map { ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor(credentialID: $0.id, transports: $0.transports) }
        key.userVerificationPreference = verification
        return [platform, key]
    }

    private func registration(_ body: [String: Any], rp: String, clientData: ASPublicKeyCredentialClientData) -> [ASAuthorizationRequest]? {
        guard let user = body["user"] as? [String: Any], let userID = Self.data(user["id"]), (1...64).contains(userID.count),
              let name = user["name"] as? String, name.utf8.count <= 1_024 else { return nil }
        let display = (user["displayName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? name
        guard display.utf8.count <= 1_024 else { return nil }
        let verification = Self.verification(body["userVerification"])
        let attestation = Self.attestation(body["attestation"])
        let excluded = Self.descriptors(body["excludeCredentials"])
        let attachment = body["authenticatorAttachment"] as? String
        // No list means ES256 or RS256, as the standard has it.
        let algorithms = (body["algorithms"] as? [Int]).flatMap { $0.isEmpty ? nil : $0 } ?? [-7, -257]
        var requests: [ASAuthorizationRequest] = []
        // A passkey from the Mac is always ES256: offered only to a site that takes it.
        if attachment != "cross-platform", algorithms.contains(-7) {
            let platform = ASAuthorizationPlatformPublicKeyCredentialProvider(relyingPartyIdentifier: rp)
                .createCredentialRegistrationRequest(clientData: clientData, name: name, userID: userID)
            platform.displayName = display
            platform.userVerificationPreference = verification
            platform.attestationPreference = attestation
            platform.excludedCredentials = excluded.map { ASAuthorizationPlatformPublicKeyCredentialDescriptor(credentialID: $0.id) }
            requests.append(platform)
        }
        if attachment != "platform" {
            let key = ASAuthorizationSecurityKeyPublicKeyCredentialProvider(relyingPartyIdentifier: rp)
                .createCredentialRegistrationRequest(clientData: clientData, displayName: display, name: name, userID: userID)
            key.credentialParameters = algorithms.map { ASAuthorizationPublicKeyCredentialParameters(algorithm: ASCOSEAlgorithmIdentifier(rawValue: $0)) }
            key.userVerificationPreference = verification
            key.attestationPreference = attestation
            switch body["residentKey"] as? String {
            case "required": key.residentKeyPreference = .required
            case "preferred": key.residentKeyPreference = .preferred
            default: key.residentKeyPreference = .discouraged
            }
            key.excludedCredentials = excluded.map { ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor(credentialID: $0.id, transports: $0.transports) }
            requests.append(key)
        }
        return requests
    }

    /// The relying party is the page's host, or a domain above it that is still a site of its own:
    /// never another site, an address, or a suffix anyone can register under (com, co.uk, github.io).
    func fits(_ rp: String, _ host: String) -> Bool {
        if rp == host { return true }
        guard host.hasSuffix("." + rp), let suffixes else { return false }
        return suffixes.registrableDomain(of: rp) != nil
    }

    // MARK: - Answers

    private func finish(_ value: [String: Any]) {
        let answer = self.answer
        clear()
        answer?(value)
    }

    private func clear() {
        controller = nil
        token = nil
        answer = nil
    }

    private static func failure(_ name: String, _ message: String) -> [String: Any] { ["error": name, "message": message] }

    static func assertionReply(id: Data, clientData: Data, authenticatorData: Data, signature: Data, user: Data, attachment: String) -> [String: Any] {
        ["kind": "get", "id": text(id), "clientDataJSON": text(clientData), "authenticatorData": text(authenticatorData),
         "signature": text(signature), "userHandle": text(user), "attachment": attachment]
    }

    static func registrationReply(id: Data, clientData: Data, attestation: Data, transports: [String], attachment: String) -> [String: Any] {
        var reply: [String: Any] = ["kind": "create", "id": text(id), "clientDataJSON": text(clientData),
                                    "attestationObject": text(attestation), "transports": transports, "attachment": attachment]
        if let data = authenticatorData(inAttestation: attestation) {
            reply["authenticatorData"] = text(data)
            if let key = publicKey(inAuthenticatorData: data) {
                reply["publicKeyAlgorithm"] = key.algorithm
                if let der = key.der { reply["publicKey"] = text(der) }
            }
        }
        return reply
    }

    // MARK: - Bytes

    static func data(_ value: Any?) -> Data? {
        guard var text = value as? String, text.utf8.count <= 8_192 else { return nil }
        text = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while text.count % 4 != 0 { text += "=" }
        return Data(base64Encoded: text)
    }

    static func text(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    private static func descriptors(_ value: Any?) -> [(id: Data, transports: [ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor.Transport])] {
        (value as? [[String: Any]] ?? []).compactMap { item in
            guard let id = data(item["id"]) else { return nil }
            let named = (item["transports"] as? [String] ?? []).compactMap { name -> ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor.Transport? in
                switch name {
                case "usb": .usb
                case "nfc": .nfc
                case "ble": .bluetooth
                default: nil
                }
            }
            return (id, named.isEmpty ? ASAuthorizationSecurityKeyPublicKeyCredentialDescriptor.Transport.allSupported : named)
        }
    }

    private static func verification(_ value: Any?) -> ASAuthorizationPublicKeyCredentialUserVerificationPreference {
        switch value as? String {
        case "required": .required
        case "discouraged": .discouraged
        default: .preferred
        }
    }

    private static func attestation(_ value: Any?) -> ASAuthorizationPublicKeyCredentialAttestationKind {
        switch value as? String {
        case "direct": .direct
        case "indirect": .indirect
        case "enterprise": .enterprise
        default: .none
        }
    }

    /// The authenticator data inside an attestation object, a CBOR map with it under "authData".
    static func authenticatorData(inAttestation object: Data) -> Data? {
        var reader = CBOR(bytes: [UInt8](object))
        guard let pairs = reader.mapCount() else { return nil }
        for _ in 0..<pairs {
            guard let key = reader.text() else { return nil }
            if key == "authData" { return reader.blob().map { Data($0) } }
            guard reader.skip() else { return nil }
        }
        return nil
    }

    /// The new credential's algorithm and public key as `getPublicKey()` returns it: DER for P-256 and
    /// Ed25519, the two kinds passkeys and security keys make; sites read others from the attestation.
    static func publicKey(inAuthenticatorData data: Data) -> (algorithm: Int, der: Data?)? {
        let bytes = [UInt8](data)
        guard bytes.count > 55, bytes[32] & 0x40 != 0 else { return nil }
        let start = 55 + (Int(bytes[53]) << 8 | Int(bytes[54]))
        guard start < bytes.count else { return nil }
        var reader = CBOR(bytes: Array(bytes[start...]))
        guard let pairs = reader.mapCount() else { return nil }
        var fields: [Int: Any] = [:]
        for _ in 0..<pairs {
            guard let key = reader.int() else { return nil }
            switch reader.major {
            case 0, 1: fields[key] = reader.int()
            case 2: fields[key] = reader.blob()
            default: guard reader.skip() else { return nil }
            }
        }
        guard let algorithm = fields[3] as? Int else { return nil }
        let x = fields[-2] as? [UInt8]
        switch (fields[1] as? Int, fields[-1] as? Int) {
        case (2, 1):
            guard let x, x.count == 32, let y = fields[-3] as? [UInt8], y.count == 32 else { return (algorithm, nil) }
            let head: [UInt8] = [0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x02, 0x01,
                                 0x06, 0x08, 0x2A, 0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x03, 0x42, 0x00, 0x04]
            return (algorithm, Data(head + x + y))
        case (1, 6):
            guard let x, x.count == 32 else { return (algorithm, nil) }
            return (algorithm, Data([0x30, 0x2A, 0x30, 0x05, 0x06, 0x03, 0x2B, 0x65, 0x70, 0x03, 0x21, 0x00] + x))
        default:
            return (algorithm, nil)
        }
    }
}

extension PasskeyCeremony: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    public func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        anchor ?? NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
    }

    public func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard controller === self.controller else { return }
        let credential = authorization.credential
        if let got = credential as? ASAuthorizationPublicKeyCredentialAssertion {
            let attachment = (credential as? ASAuthorizationPlatformPublicKeyCredentialAssertion)?.attachment
            finish(Self.assertionReply(id: got.credentialID, clientData: got.rawClientDataJSON, authenticatorData: got.rawAuthenticatorData,
                                       signature: got.signature, user: got.userID, attachment: attachment == .platform ? "platform" : "cross-platform"))
        } else if let made = credential as? ASAuthorizationPublicKeyCredentialRegistration {
            let platform = credential as? ASAuthorizationPlatformPublicKeyCredentialRegistration
            finish(Self.registrationReply(id: made.credentialID, clientData: made.rawClientDataJSON, attestation: made.rawAttestationObject ?? Data(),
                                          transports: platform == nil ? ["usb"] : ["hybrid", "internal"],
                                          attachment: platform?.attachment == .platform ? "platform" : "cross-platform"))
        } else {
            finish(Self.failure("NotAllowedError", "The authenticator answered with something else."))
        }
    }

    public func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: any Error) {
        guard controller === self.controller else { return }
        // A credential it already holds is what a site is told; anything else it may not tell apart.
        let error = error as NSError
        if error.domain == ASAuthorizationError.errorDomain, error.code == ASAuthorizationError.Code.matchedExcludedCredential.rawValue {
            finish(Self.failure("InvalidStateError", "The authenticator already holds a credential for this account."))
        } else {
            finish(Self.failure("NotAllowedError", "The operation either timed out or was not allowed."))
        }
    }
}

/// Just enough CBOR to read an attestation object: maps, numbers, text and byte strings, and a step over the rest.
private struct CBOR {
    let bytes: [UInt8]
    var at = 0

    init(bytes: [UInt8]) { self.bytes = bytes }

    var major: UInt8? { at < bytes.count ? bytes[at] >> 5 : nil }

    private mutating func head() -> (major: UInt8, value: UInt64)? {
        guard at < bytes.count else { return nil }
        let first = bytes[at]
        at += 1
        let info = first & 0x1F
        switch info {
        case 0..<24:
            return (first >> 5, UInt64(info))
        case 24...27:
            let size = 1 << Int(info - 24)
            guard at + size <= bytes.count else { return nil }
            let value = bytes[at..<(at + size)].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            at += size
            return (first >> 5, value)
        default:
            return nil
        }
    }

    mutating func mapCount() -> Int? {
        guard let (major, value) = head(), major == 5, value < 1024 else { return nil }
        return Int(value)
    }

    mutating func int() -> Int? {
        guard let (major, value) = head(), value < UInt64(Int.max) else { return nil }
        switch major {
        case 0: return Int(value)
        case 1: return -1 - Int(value)
        default: return nil
        }
    }

    mutating func text() -> String? {
        guard let (major, value) = head(), major == 3, value <= UInt64(bytes.count - at) else { return nil }
        defer { at += Int(value) }
        return String(bytes: bytes[at..<(at + Int(value))], encoding: .utf8)
    }

    mutating func blob() -> [UInt8]? {
        guard let (major, value) = head(), major == 2, value <= UInt64(bytes.count - at) else { return nil }
        defer { at += Int(value) }
        return Array(bytes[at..<(at + Int(value))])
    }

    mutating func skip(depth: Int = 0) -> Bool {
        guard depth < 16, let (major, value) = head() else { return false }
        switch major {
        case 0, 1, 7:
            return true
        case 2, 3:
            guard value <= UInt64(bytes.count - at) else { return false }
            at += Int(value)
            return true
        case 4:
            guard value < 1024 else { return false }
            return (0..<value).allSatisfy { _ in skip(depth: depth + 1) }
        case 5:
            guard value < 1024 else { return false }
            return (0..<value).allSatisfy { _ in skip(depth: depth + 1) && skip(depth: depth + 1) }
        case 6:
            return skip(depth: depth + 1)
        default:
            return false
        }
    }
}

/// Hands the page's requests to the ceremony, from Aero's world; the frame is WebKit's to say.
final class PasskeyBridge: NSObject, WKScriptMessageHandlerWithReply {
    static let name = "aeroPasskeys"
    weak var ceremony: PasskeyCeremony?

    init(ceremony: PasskeyCeremony) { self.ceremony = ceremony }

    @MainActor
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        guard let body = message.body as? [String: Any], let ceremony,
              let webView = message.webView, let page = webView.navigationDelegate as? BrowserPage else {
            return replyHandler(nil, "Not a request")
        }
        if body["kind"] as? String == "cancel" {
            ceremony.cancel(token: body["token"] as? String)
            return replyHandler(true, nil)
        }
        let caller = PasskeyCeremony.Caller(origin: message.frameInfo.securityOrigin,
                                            pageOrigin: webView.url.flatMap(SiteOrigin.init(url:)), window: webView.window)
        let generation = page.documentGeneration
        let pageURL = webView.url
        ceremony.perform(body, from: caller, isCurrent: { [weak webView, weak page] in
            guard let webView, let page else { return false }
            return (webView.navigationDelegate as? BrowserPage) === page
                && page.documentGeneration == generation
                && webView.window === caller.window && webView.url == pageURL
        }) { replyHandler($0, nil) }
    }
}

@MainActor
enum PasskeyScripts {
    static let asked = "aero-passkeys-ask"
    static let answered = "aero-passkeys-answer"

    /// Without the entitlement WebKit exposes the passkey API but cannot answer it, so sites offer a
    /// passkey and strand the person. Hidden, sites go straight to the password, unless an extension
    /// that keeps passkeys (1Password, Bitwarden) answers the requests itself.
    static let withoutPasskeys = WKUserScript(source: """
        (function () {
          var real = window.PublicKeyCredential;
          if (!real) return;
          var claimed = false;
          function answered() {
            if (claimed) return true;
            try {
              if (navigator.credentials && Object.getOwnPropertyDescriptor(navigator.credentials, 'get')) claimed = true;
              else if ((new Error().stack || '').indexOf('-extension://') >= 0) claimed = true;
            } catch (e) {}
            return claimed;
          }
          try {
            Object.defineProperty(window, 'PublicKeyCredential', {
              configurable: true,
              get: function () { return answered() ? real : undefined; },
              set: function (value) { real = value; }
            });
          } catch (e) {
            try { delete window.PublicKeyCredential; } catch (ignored) {}
            return;
          }
          var proto = CredentialsContainer.prototype;
          ['get', 'create'].forEach(function (name) {
            var native = proto[name];
            try {
              Object.defineProperty(proto, name, {
                configurable: true, writable: true,
                value: function (options) {
                  if (!options || !options.publicKey) return native.apply(this, arguments);
                  var signal = options.signal;
                  if (name === 'get' && options.mediation === 'conditional') {
                    return new Promise(function (resolve, reject) {
                      if (!signal) return;
                      var aborted = function () { return signal.reason || new DOMException('The operation was aborted.', 'AbortError'); };
                      if (signal.aborted) return reject(aborted());
                      signal.addEventListener('abort', function () { reject(aborted()); }, { once: true });
                    });
                  }
                  return Promise.reject(new DOMException('The operation either timed out or was not allowed.', 'NotAllowedError'));
                }
              });
            } catch (e) {}
          });
        })();
        """, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page)

    /// In the page's world, before the site's scripts: `navigator.credentials` answers public key
    /// requests through Aero and anything else as before. Nothing of Aero's is visible there: requests
    /// leave as window events for the bridge in Aero's world.
    static let page = WKUserScript(source: """
        (function () {
          if (!window.PublicKeyCredential || !window.CredentialsContainer) return;
          var proto = CredentialsContainer.prototype;
          var mark = Symbol.for('aero.passkeys');
          if (proto[mark]) return;
          try { Object.defineProperty(proto, mark, { value: navigator.credentials }); } catch (e) { return; }
          var nativeGet = proto.get, nativeCreate = proto.create;
          var refused = 'The operation either timed out or was not allowed.';
          function bytes(source) {
            if (source instanceof ArrayBuffer) return new Uint8Array(source);
            if (ArrayBuffer.isView(source)) return new Uint8Array(source.buffer, source.byteOffset, source.byteLength);
            throw new TypeError('Expected an ArrayBuffer or a view of one.');
          }
          function encode(source) {
            var b = bytes(source), s = '';
            for (var i = 0; i < b.length; i++) s += String.fromCharCode(b[i]);
            return btoa(s).replace(/\\+/g, '-').replace(/\\//g, '_').replace(/=+$/, '');
          }
          function decode(text) {
            var s = (text || '').replace(/-/g, '+').replace(/_/g, '/');
            while (s.length % 4) s += '=';
            var raw = atob(s), out = new Uint8Array(raw.length);
            for (var i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i);
            return out.buffer;
          }
          function descriptors(list) {
            return Array.prototype.map.call(list || [], function (c) {
              return { id: encode(c.id), transports: Array.prototype.slice.call(c.transports || []) };
            });
          }
          function aborted(signal) {
            return signal.reason !== undefined ? signal.reason : new DOMException('The operation was aborted.', 'AbortError');
          }
          function define(target, values, hidden) {
            Object.keys(values).forEach(function (k) {
              Object.defineProperty(target, k, { value: values[k], enumerable: !hidden, configurable: true });
            });
            return target;
          }
          function credential(reply, extensions) {
            var response, made = reply.kind === 'create';
            if (made) {
              response = Object.create(AuthenticatorAttestationResponse.prototype);
              define(response, { clientDataJSON: decode(reply.clientDataJSON), attestationObject: decode(reply.attestationObject) });
              define(response, {
                getTransports: function () { return (reply.transports || []).slice(); },
                getAuthenticatorData: function () { return decode(reply.authenticatorData); },
                getPublicKey: function () { return reply.publicKey ? decode(reply.publicKey) : null; },
                getPublicKeyAlgorithm: function () { return reply.publicKeyAlgorithm != null ? reply.publicKeyAlgorithm : -7; }
              }, true);
            } else {
              response = Object.create(AuthenticatorAssertionResponse.prototype);
              define(response, {
                clientDataJSON: decode(reply.clientDataJSON),
                authenticatorData: decode(reply.authenticatorData),
                signature: decode(reply.signature),
                userHandle: reply.userHandle ? decode(reply.userHandle) : null
              });
            }
            var results = {};
            if (made && extensions && extensions.credProps && reply.attachment === 'platform') results.credProps = { rk: true };
            var attachment = reply.attachment || null;
            var json = { id: reply.id, rawId: reply.id, type: 'public-key', authenticatorAttachment: attachment, clientExtensionResults: results };
            json.response = made
              ? { clientDataJSON: reply.clientDataJSON, attestationObject: reply.attestationObject, authenticatorData: reply.authenticatorData,
                  transports: (reply.transports || []).slice(), publicKeyAlgorithm: reply.publicKeyAlgorithm != null ? reply.publicKeyAlgorithm : -7 }
              : { clientDataJSON: reply.clientDataJSON, authenticatorData: reply.authenticatorData, signature: reply.signature };
            if (made && reply.publicKey) json.response.publicKey = reply.publicKey;
            if (!made && reply.userHandle) json.response.userHandle = reply.userHandle;
            var result = Object.create(PublicKeyCredential.prototype);
            define(result, { id: reply.id, rawId: decode(reply.id), type: 'public-key', authenticatorAttachment: attachment, response: response });
            return define(result, {
              getClientExtensionResults: function () { return JSON.parse(JSON.stringify(results)); },
              toJSON: function () { return JSON.parse(JSON.stringify(json)); }
            }, true);
          }
          var waiting = {};
          window.addEventListener('\(answered)', function (event) {
            var data;
            try { data = JSON.parse(event.detail); } catch (e) { return; }
            var done = data && waiting[data.token];
            if (!done) return;
            delete waiting[data.token];
            done(data.reply);
          });
          function ask(message) {
            return new Promise(function (resolve) {
              if (message.kind === 'cancel') resolve(true); else waiting[message.token] = resolve;
              window.dispatchEvent(new CustomEvent('\(asked)', { detail: JSON.stringify(message) }));
            });
          }
          function send(request, signal, extensions) {
            if (signal && signal.aborted) return Promise.reject(aborted(signal));
            request.token = Math.random().toString(36).slice(2);
            return new Promise(function (resolve, reject) {
              var settled = false;
              function onAbort() {
                if (settled) return;
                settled = true;
                delete waiting[request.token];
                ask({ kind: 'cancel', token: request.token });
                reject(aborted(signal));
              }
              if (signal) signal.addEventListener('abort', onAbort, { once: true });
              ask(request).then(function (reply) {
                if (settled) return;
                settled = true;
                if (signal) signal.removeEventListener('abort', onAbort);
                if (!reply || reply.error) {
                  var name = (reply && reply.error) || 'NotAllowedError';
                  var message = (reply && reply.message) || refused;
                  return reject(name === 'TypeError' ? new TypeError(message) : new DOMException(message, name));
                }
                resolve(credential(reply, extensions));
              }, function () {
                if (settled) return;
                settled = true;
                if (signal) signal.removeEventListener('abort', onAbort);
                reject(new DOMException(refused, 'NotAllowedError'));
              });
            });
          }
          function replace(target, name, value) {
            try { Object.defineProperty(target, name, { value: value, configurable: true, writable: true }); } catch (e) {}
          }
          replace(proto, 'get', function get(options) {
            if (!options || !options.publicKey) return nativeGet.apply(this, arguments);
            var signal = options.signal, pk = options.publicKey, request;
            if (options.mediation === 'conditional') {
              return new Promise(function (resolve, reject) {
                if (!signal) return;
                if (signal.aborted) return reject(aborted(signal));
                signal.addEventListener('abort', function () { reject(aborted(signal)); }, { once: true });
              });
            }
            try {
              request = { kind: 'get', challenge: encode(pk.challenge), rpId: pk.rpId || null,
                          allowCredentials: descriptors(pk.allowCredentials), userVerification: pk.userVerification || 'preferred' };
            } catch (e) { return Promise.reject(e); }
            return send(request, signal, pk.extensions);
          });
          replace(proto, 'create', function create(options) {
            if (!options || !options.publicKey) return nativeCreate.apply(this, arguments);
            var pk = options.publicKey, selection = pk.authenticatorSelection || {}, request;
            if (options.mediation === 'conditional') return Promise.reject(new DOMException(refused, 'NotAllowedError'));
            try {
              request = {
                kind: 'create', challenge: encode(pk.challenge), rp: { id: (pk.rp && pk.rp.id) || null },
                user: { id: encode(pk.user.id), name: String(pk.user.name), displayName: pk.user.displayName ? String(pk.user.displayName) : '' },
                algorithms: Array.prototype.map.call(pk.pubKeyCredParams || [], function (p) { return p.alg; }),
                excludeCredentials: descriptors(pk.excludeCredentials),
                authenticatorAttachment: selection.authenticatorAttachment || null,
                residentKey: selection.residentKey || (selection.requireResidentKey ? 'required' : 'discouraged'),
                userVerification: selection.userVerification || 'preferred', attestation: pk.attestation || 'none'
              };
            } catch (e) { return Promise.reject(e); }
            return send(request, options.signal, pk.extensions);
          });
          var claimed = false;
          function extensionAnswers() {
            if (claimed) return true;
            try {
              if (navigator.credentials && Object.getOwnPropertyDescriptor(navigator.credentials, 'get')) claimed = true;
              else if ((new Error().stack || '').indexOf('-extension://') >= 0) claimed = true;
            } catch (e) {}
            return claimed;
          }
          var P = PublicKeyCredential;
          replace(P, 'isUserVerifyingPlatformAuthenticatorAvailable', function () { return Promise.resolve(true); });
          replace(P, 'isConditionalMediationAvailable', function () { return Promise.resolve(extensionAnswers()); });
          var nativeCapabilities = P.getClientCapabilities;
          if (typeof nativeCapabilities === 'function') {
            replace(P, 'getClientCapabilities', function () {
              var field = extensionAnswers();
              function ours(c) {
                c = Object.assign({}, c);
                Object.keys(c).forEach(function (k) { if (k.indexOf('extension:') === 0 && k !== 'extension:credProps') c[k] = false; });
                return Object.assign(c, {
                  conditionalCreate: false, conditionalGet: field, conditionalMediation: field, relatedOrigins: false,
                  signalAllAcceptedCredentials: false, signalCurrentUserDetails: false, signalUnknownCredential: false,
                  hybridTransport: true, passkeyPlatformAuthenticator: true, userVerifyingPlatformAuthenticator: true
                });
              }
              return nativeCapabilities.call(P).then(ours, function () { return ours({}); });
            });
          }
        })();
        """, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page)

    /// In Aero's world, where the handler is: relays page events as they are, the answers back as events.
    static let bridge = WKUserScript(source: """
        (function () {
          var handler = window.webkit && webkit.messageHandlers && webkit.messageHandlers.\(PasskeyBridge.name);
          if (!handler || globalThis.aeroPasskeysBridged) return;
          globalThis.aeroPasskeysBridged = true;
          window.addEventListener('\(asked)', function (event) {
            var message;
            try { message = JSON.parse(event.detail); } catch (e) { return; }
            if (!message || typeof message !== 'object' || typeof message.token !== 'string') return;
            function answer(reply) {
              window.dispatchEvent(new CustomEvent('\(answered)', { detail: JSON.stringify({ token: message.token, reply: reply }) }));
            }
            handler.postMessage(message).then(function (reply) {
              if (message.kind !== 'cancel') answer(reply);
            }, function () {
              if (message.kind !== 'cancel') answer(null);
            });
          });
        })();
        """, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: PageScripts.world)
}
