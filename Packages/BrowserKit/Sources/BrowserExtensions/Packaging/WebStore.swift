import BrowserCore
import Foundation
import WebKit

/// The Chrome Web Store: its extension pages, where Aero puts its own install button, and its update service, which
/// serves packages and says whether a newer one exists. See docs/EXTENSIONS.md › Installing.
@MainActor
public enum WebStore {
    public enum Failure: Error { case unavailable }

    nonisolated private static let host = "chromewebstore.google.com"
    private static let service = URL(string: "https://clients2.google.com/service/update2/crx")!
    /// The Chromium version the service is asked for packages that run on.
    private static let chromiumVersion = "140.0"
    nonisolated private static let session = URLSession.anonymous(requestTimeout: 60, resourceTimeout: 300)

    /// The extension a store page is about: `/detail/<name>/<identifier>` or `/detail/<identifier>`.
    nonisolated public static func extensionID(on url: URL) -> String? {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.host() == host else { return nil }
        let parts = url.pathComponents
        guard parts.count >= 3, parts[1] == "detail", let last = parts.last, InstalledExtension.isValidIdentifier(last) else { return nil }
        return last
    }

    nonisolated public static func extensionID(in text: String) -> String? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if InstalledExtension.isValidIdentifier(text) { return text }
        return URL(string: text).flatMap(extensionID(on:))
    }

    public static func package(_ identifier: String) async throws -> Data {
        let (data, response) = try await session.data(from: query(identifier, version: nil, redirect: true))
        guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else { throw Failure.unavailable }
        return data
    }

    /// The newer version the store has, if any.
    public static func newerVersion(of identifier: String, than version: String) async throws -> String? {
        let (data, response) = try await session.data(from: query(identifier, version: version, redirect: false))
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.unavailable }
        let reader = UpdateCheck()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse() else { throw Failure.unavailable }
        return reader.status == "ok" ? reader.version.flatMap { $0 == version ? nil : $0 } : nil
    }

    private static func query(_ identifier: String, version: String?, redirect: Bool) -> URL {
        let request = "id=\(identifier)&v=\(version ?? "")&uc"
        return service.appending(queryItems: [
            URLQueryItem(name: "response", value: redirect ? "redirect" : "updatecheck"),
            URLQueryItem(name: "prodversion", value: chromiumVersion),
            URLQueryItem(name: "acceptformat", value: "crx3"),
            URLQueryItem(name: "x", value: request)
        ])
    }

    // MARK: - Install button

    private static let world = WKContentWorld.world(name: "AeroWebStore")
    private static let handlerName = "aeroWebStore"

    /// On the Chrome Web Store, puts Aero's install button in place of the store's grey one. The store's
    /// markup is generated, so nothing leans on its class names: its button is the disabled one naming Chrome. The page never says what to install;
    /// Aero reads that from the tab's address. See docs/EXTENSIONS.md › Installing.
    private static let buttonScript = WKUserScript(source: """
        (() => {
            if (location.hostname !== "chromewebstore.google.com") return;
            const bridge = (body) => window.webkit.messageHandlers.\(handlerName).postMessage(body);
            const show = (button, state) => {
                if (!state) { button.previousElementSibling.style.display = ""; button.remove(); return; }
                const texts = document.createTreeWalker(button, NodeFilter.SHOW_TEXT);
                let last = null;
                for (let node = texts.nextNode(); node; node = texts.nextNode()) if (node.nodeValue.trim()) last = node;
                if (last) last.nodeValue = state.title; else button.textContent = state.title;
                button.disabled = !state.enabled;
            };
            const place = () => {
                for (const theirs of document.querySelectorAll("button[disabled]:not([data-aero])")) {
                    if (!/chrome/i.test(theirs.textContent)) continue;
                    const ours = theirs.cloneNode(true);
                    for (const name of ["jsaction", "jscontroller", "jsname", "jslog", "aria-describedby"]) ours.removeAttribute(name);
                    ours.dataset.aero = "install";
                    ours.disabled = true;
                    theirs.dataset.aero = "hidden";
                    theirs.style.display = "none";
                    theirs.after(ours);
                    bridge("state").then((state) => show(ours, state));
                }
            };
            // Caught on the window, before the store's own handlers on the document see the click.
            window.addEventListener("click", (event) => {
                const ours = event.target.closest?.('button[data-aero="install"]');
                if (!ours) return;
                event.preventDefault();
                event.stopImmediatePropagation();
                // Only the person's click: the store's own scripts click buttons too.
                if (ours.disabled || !event.isTrusted) return;
                ours.disabled = true;
                bridge("install").then((state) => show(ours, state));
            }, true);
            // The store rewrites itself as it moves between extensions. A timer, not a frame: a tab out of
            // sight gets no frames.
            let queued = false;
            new MutationObserver(() => {
                if (queued) return;
                queued = true;
                setTimeout(() => { queued = false; place(); }, 60);
            }).observe(document.documentElement, { childList: true, subtree: true });
            place();
        })();
        """, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: world)

    static func addButton(to controller: WKUserContentController, profileID: UUID, registry: ExtensionRegistry) {
        controller.addUserScript(buttonScript)
        controller.addScriptMessageHandler(ButtonBridge(profileID: profileID, registry: registry), contentWorld: world, name: handlerName)
    }

    /// Answers the store script from Aero's world, which pages cannot post to. The page never says what to install:
    /// the extension is read from the address of the page that asks, in the profile the page belongs to.
    private final class ButtonBridge: NSObject, WKScriptMessageHandlerWithReply {
        let profileID: UUID
        weak var registry: ExtensionRegistry?

        init(profileID: UUID, registry: ExtensionRegistry) {
            self.profileID = profileID
            self.registry = registry
        }

        @MainActor
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) async -> (Any?, String?) {
            guard message.frameInfo.isMainFrame, let url = message.webView?.url, let identifier = WebStore.extensionID(on: url),
                  let host = registry?.host else { return (nil, nil) }
            if message.body as? String == "install" { await host.installFromWebStore(identifier, inProfile: profileID) }
            let button = host.webStoreButton(for: identifier, inProfile: profileID)
            return (["title": button.title, "enabled": button.isEnabled], nil)
        }
    }

    /// Reads `<updatecheck status="…" version="…"/>` from the service's answer.
    private final class UpdateCheck: NSObject, XMLParserDelegate {
        var status: String?
        var version: String?

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            guard name == "updatecheck" else { return }
            status = attributes["status"]
            version = attributes["version"]
        }
    }
}

/// What the Chrome Web Store's install button says, and whether it can be pressed.
public struct WebStoreButton: Sendable {
    public let title: String
    public let isEnabled: Bool

    public init(title: String, isEnabled: Bool) {
        self.title = title
        self.isEnabled = isEnabled
    }
}
