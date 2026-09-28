import BrowserCore
import Foundation
import WebKit

public enum PasswordField: String, Sendable {
    case username, password, newPassword
}

/// What a page's sign-in or sign-up form reported. See docs/PASSWORDS.md › Detecting forms.
public enum PasswordFormEvent: Sendable {
    /// A field gained focus; its frame in the web view, in points, when the frame could say where it is.
    case focused(PasswordField, CGRect?)
    case blurred
    /// The person typed in the field, or pressed Escape: they are not choosing a saved login.
    case typed
    /// The first step of a sign-in submitted an account without a password field.
    case usernameSubmitted(String)
    case submitted(username: String, password: String)
}

/// The frame a form event came from, with its origin as WebKit knows it rather than as the page says.
@MainActor
public struct PasswordFrame {
    let info: WKFrameInfo
    public let origin: SiteOrigin
}

@MainActor
enum PasswordScripts {
    static let handlerName = "aeroPasswords"
    static let maximumUsernameLength = 512
    static let maximumPasswordLength = 1024

    /// In every frame, in Aero's world: finds sign-in and sign-up fields, reports focus and submissions,
    /// and fills only the form of the focused field, through the native setter and the events a
    /// keystroke fires, so frameworks see the new value.
    static let forms = WKUserScript(source: """
        (() => {
            if (globalThis.aeroPasswords) return;
            const handler = window.webkit?.messageHandlers?.\(handlerName);
            if (!handler) return;
            const post = (body) => handler.postMessage(body);
            const textTypes = new Set(["text", "email", "tel", "url", ""]);
            const hint = (input) => (input.getAttribute("autocomplete") || "").toLowerCase().split(/\\s+/);
            const usable = (node) => node instanceof HTMLInputElement && !node.disabled && !node.readOnly && node.type !== "hidden";
            const visible = (input) => { const box = input.getBoundingClientRect(); return box.width > 0 && box.height > 0; };
            const scopeOf = (input) => input.form || input.getRootNode();
            const inputs = (scope) => Array.from(scope.querySelectorAll("input")).filter(usable);
            const secrets = (scope) => inputs(scope).filter((input) => input.type === "password" && visible(input));
            const isNew = (input, all) => {
                const words = hint(input);
                if (words.includes("new-password")) return true;
                if (words.includes("current-password")) return false;
                return all.length > 1;
            };
            const accountField = (input) => textTypes.has(input.type) && visible(input) &&
                (input.type === "email" || hint(input).includes("username") ||
                 /user(?:name)?|e-?mail|login|identifier/i.test(input.name + " " + input.id));
            const fields = (scope) => {
                const all = inputs(scope), secret = secrets(scope);
                const fresh = secret.filter((input) => isNew(input, secret));
                const current = secret.find((input) => !isNew(input, secret)) || null;
                let username = all.find((input) => textTypes.has(input.type) && visible(input) && hint(input).includes("username")) || null;
                if (!username && secret.length) {
                    const before = all.slice(0, all.indexOf(secret[0])).filter((input) => textTypes.has(input.type) && visible(input));
                    username = before[before.length - 1] || null;
                }
                if (!username && !secret.length) username = all.find(accountField) || null;
                return { username, current, fresh };
            };
            const kindOf = (node) => {
                if (!usable(node)) return null;
                const found = fields(scopeOf(node));
                if (node.type === "password") return found.fresh.includes(node) ? "newPassword" : "password";
                if (node === found.username) return "username";
                return null;
            };
            // In the top document's coordinates, through same-origin parent frames; null past another origin.
            const place = (input) => {
                const box = input.getBoundingClientRect();
                let x = box.left, y = box.top, view = window;
                try {
                    while (view !== view.top) {
                        const frame = view.frameElement;
                        if (!frame) return null;
                        const outer = frame.getBoundingClientRect();
                        x += outer.left + frame.clientLeft;
                        y += outer.top + frame.clientTop;
                        view = view.parent;
                    }
                } catch (error) { return null; }
                return { x, y, width: box.width, height: box.height };
            };
            let focused = null, typed = false;
            document.addEventListener("focusin", (event) => {
                const node = event.composedPath()[0];
                const kind = kindOf(node);
                if (!kind) return;
                focused = node;
                typed = false;
                post({ kind: "focus", field: kind, rect: place(node) });
            }, true);
            const typing = (event) => {
                if (!event.isTrusted || typed || event.composedPath()[0] !== focused) return;
                typed = true;
                post({ kind: "typed" });
            };
            document.addEventListener("input", typing, true);
            document.addEventListener("keydown", (event) => { if (event.key === "Escape") typing(event); }, true);
            document.addEventListener("focusout", (event) => {
                if (event.composedPath()[0] === focused) post({ kind: "blur" });
            }, true);
            let lastSent = "";
            const capture = (scope, submitsPassword) => {
                const found = fields(scope);
                const secret = found.fresh[0] || found.current;
                let body;
                if (secret) {
                    if (!submitsPassword || !secret.value) return;
                    body = { kind: "submit", username: found.username ? found.username.value : "", password: secret.value };
                } else {
                    if (!found.username?.value) return;
                    body = { kind: "username", username: found.username.value };
                }
                const key = body.kind + "\\u0001" + body.username + "\\u0001" + (body.password || "");
                if (key === lastSent) return;
                lastSent = key;
                setTimeout(() => { if (lastSent === key) lastSent = ""; }, 1000);
                post(body);
            };
            document.addEventListener("submit", (event) => {
                if (event.target instanceof HTMLFormElement) capture(event.target, true);
            }, true);
            // Many sign-ins use a scripted button instead of submitting a form.
            const sender = 'button[type="submit"], button:not([type]), input[type="submit"], input[type="image"]';
            document.addEventListener("click", (event) => {
                if (!event.isTrusted) return;
                const button = event.composedPath().find((node) => node instanceof Element && node.matches('button, input[type="submit"], input[type="image"]'));
                const scope = button && (button.form || (focused && scopeOf(focused)));
                if (scope) capture(scope, button.matches(sender));
            }, true);
            document.addEventListener("keydown", (event) => {
                if (!event.isTrusted || event.key !== "Enter" || event.isComposing) return;
                const node = event.composedPath()[0];
                if (node instanceof HTMLInputElement && kindOf(node)) capture(scopeOf(node), node.type === "password");
            }, true);
            const setValue = (input, value) => {
                Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set.call(input, value);
                input.dispatchEvent(new Event("input", { bubbles: true, composed: true }));
                input.dispatchEvent(new Event("change", { bubbles: true }));
            };
            globalThis.aeroPasswords = {
                fill(username, password, origin) {
                    if (location.origin !== origin || !focused?.isConnected) return false;
                    const found = fields(scopeOf(focused));
                    if (found.username && username) setValue(found.username, username);
                    const secret = found.current || (focused.type === "password" ? focused : null);
                    if (secret) setValue(secret, password);
                    return true;
                },
                fillNew(password, origin) {
                    if (location.origin !== origin || !focused?.isConnected) return false;
                    const found = fields(scopeOf(focused));
                    const targets = found.fresh.length ? found.fresh : focused.type === "password" ? [focused] : [];
                    targets.forEach((input) => setValue(input, password));
                    return targets.length > 0;
                }
            };
        })();
        """, injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: PageScripts.world)

    static let fill = "return globalThis.aeroPasswords?.fill(username, password, origin) ?? false;"
    static let fillNew = "return globalThis.aeroPasswords?.fillNew(password, origin) ?? false;"
}

/// Receives form reports in Aero's world, which pages cannot post to.
final class PasswordFormBridge: NSObject, WKScriptMessageHandler {
    @MainActor
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let page = message.webView?.navigationDelegate as? BrowserPage, let body = message.body as? [String: Any] else { return }
        page.receivePasswordReport(body, from: message.frameInfo)
    }
}

extension BrowserPage {
    /// Page scripts are untrusted: the origin is the frame's, strings are bounded, anything else is dropped.
    func receivePasswordReport(_ body: [String: Any], from info: WKFrameInfo) {
        let security = info.securityOrigin
        guard let onPasswordForm, let kind = body["kind"] as? String,
              let origin = SiteOrigin(scheme: security.protocol, host: security.host, port: security.port) else { return }
        let frame = PasswordFrame(info: info, origin: origin)
        switch kind {
        case "focus":
            guard let field = (body["field"] as? String).flatMap(PasswordField.init(rawValue:)) else { return }
            onPasswordForm(.focused(field, placement(body["rect"])), frame)
        case "blur":
            onPasswordForm(.blurred, frame)
        case "typed":
            onPasswordForm(.typed, frame)
        case "username":
            guard let username = body["username"] as? String, !username.isEmpty,
                  username.count <= PasswordScripts.maximumUsernameLength else { return }
            onPasswordForm(.usernameSubmitted(username), frame)
        case "submit":
            guard let username = body["username"] as? String, username.count <= PasswordScripts.maximumUsernameLength,
                  let password = body["password"] as? String, !password.isEmpty, password.count <= PasswordScripts.maximumPasswordLength else { return }
            onPasswordForm(.submitted(username: username, password: password), frame)
        default:
            break
        }
    }

    /// Fills the focused form of `frame` with a saved login; false if the frame moved to another origin.
    public func fillLogin(username: String, password: String, in frame: PasswordFrame) async -> Bool {
        let result = try? await webView.callAsyncJavaScript(PasswordScripts.fill, arguments: ["username": username, "password": password, "origin": frame.origin.rawValue],
                                                            in: frame.info, contentWorld: PageScripts.world)
        return result as? Bool == true
    }

    /// Fills the new-password fields of the focused form, as a strong password suggestion.
    public func fillNewPassword(_ password: String, in frame: PasswordFrame) async -> Bool {
        let result = try? await webView.callAsyncJavaScript(PasswordScripts.fillNew, arguments: ["password": password, "origin": frame.origin.rawValue],
                                                            in: frame.info, contentWorld: PageScripts.world)
        return result as? Bool == true
    }

    /// CSS pixels of the top document to points of the web view.
    private func placement(_ value: Any?) -> CGRect? {
        guard let rect = value as? [String: Any], let x = rect["x"] as? Double, let y = rect["y"] as? Double,
              let width = rect["width"] as? Double, let height = rect["height"] as? Double,
              [x, y, width, height].allSatisfy(\.isFinite), width > 0, height > 0 else { return nil }
        let scale = webView.pageZoom * webView.magnification
        return CGRect(x: x * scale, y: y * scale, width: width * scale, height: height * scale)
    }
}
