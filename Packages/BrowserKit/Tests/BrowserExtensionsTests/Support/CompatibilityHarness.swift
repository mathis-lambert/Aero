import Foundation
import JavaScriptCore
import Testing
@testable import BrowserExtensions

final class CompatibilityHarness {
    let context: JSContext

    /// `prelude` runs after the stand-in for WebKit and before the layer.
    init(manifest: String = #"{"permissions": []}"#, api: String = "{}", prelude: String = "", identifier: String = String(repeating: "a", count: 32)) throws {
        context = try #require(JSContext())
        context.exceptionHandler = { _, exception in Issue.record("JavaScript exception: \(exception?.toString() ?? "")") }
        context.evaluateScript("""
            // What extension contexts have and JavaScriptCore alone does not.
            globalThis.URL = class {
                constructor(url, base) {
                    this.href = /^[a-z-]+:/.test(url) ? url : base + url.replace(/^\\//, "");
                    const [, protocol, host = "", port = "", pathname = "/", search = ""] =
                        /^([a-z-]+:)(?:\\/\\/([^/:?#]*)(?::(\\d+))?)?([^?#]*)(\\?[^#]*)?/.exec(this.href) ?? [];
                    Object.assign(this, { protocol, hostname: host, port, pathname: pathname || "/", search, origin: `${protocol}//${host}` });
                }
            };
            globalThis.queueMicrotask ??= (callback) => Promise.resolve().then(callback);
            globalThis.console ??= { error() {}, log() {} };
            globalThis.requests = [];
            globalThis.replies = {};
            globalThis.setTimeout = () => 0;
            globalThis.fetch = async (url, init) => {
                const route = url.replace("aero-extension://aero/", "").split("?")[0];
                requests.push({ route, body: JSON.parse(init.body) });
                const value = replies[route];
                const failed = value !== undefined && value !== null && value.failure !== undefined;
                return { ok: !failed, json: async () => failed ? { error: value.failure } : { value: value ?? null } };
            };
            const manifest = \(manifest);
            globalThis.chrome = Object.assign({ runtime: { id: "\(identifier)",
                getURL: (path) => "webkit-extension://base/" + path.replace(/^\\//, ""), getManifest: () => manifest } }, \(api));
            \(prelude)
            """)
        let script = try String(decoding: ExtensionCompatibility.script(), as: UTF8.self)
        context.evaluateScript(script)
    }

    @discardableResult
    func run(_ script: String) -> JSValue? { context.evaluateScript(script) }

    func string(_ expression: String) -> String? { run(expression)?.toString() }
    func bool(_ expression: String) -> Bool { run(expression)?.toBool() == true }

    /// The routes and bodies requested so far, as JSON.
    var requests: String { string("JSON.stringify(requests)") ?? "" }
}
