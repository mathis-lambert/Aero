import BrowserCore
import Foundation
import WebKit

/// What a page asks of its link preview (docs/BROWSING.md › Peek).
public enum PeekRequest: Sendable {
    /// The person presses a link hard: its preview starts loading and shows as the pressure grows. The link's frame is
    /// in the web view, in points, when the page could say where it is.
    case press(URL, CGRect?)
    /// How far the press has gone from where the preview starts to a force click, from 0 to 1.
    case pressure(Double)
    /// Preview the link, open.
    case open(URL, CGRect?)
    /// The press ended without a force click.
    case cancel
}

/// A press on a Force Touch trackpad, as the page's view reads it.
enum ForcePress: Equatable {
    /// Past halfway to a force click: the press starts a preview.
    case deep
    /// How far a deep press has gone toward a force click, from 0 to 1.
    case pressure(Double)
    case forceClick
    /// Released after `deep`, without a force click.
    case released
}

/// A force click on a link previews it over its page; WebKit's own preview is off. The view reads the trackpad's
/// pressure, and this script, in Aero's world, finds the link under the pointer, through open shadow roots. Once a
/// force click takes a link, the click that ends the press is the page's no more: it would follow the link.
@MainActor
enum PeekScripts {
    /// Longer addresses are not previewed.
    static let maximumAddressLength = 8192

    static let linkFinder = WKUserScript(source: """
        (() => {
            let swallowsClick = false;
            const deepest = (x, y) => {
                let node = document.elementFromPoint(x, y);
                while (node?.shadowRoot) {
                    const inner = node.shadowRoot.elementFromPoint(x, y);
                    if (!inner || inner === node) break;
                    node = inner;
                }
                return node;
            };
            const linkAt = (x, y) => {
                for (let node = deepest(x, y); node; node = node.parentElement ?? node.getRootNode().host ?? null) {
                    if (node.matches?.("a[href]") && typeof node.href === "string" && /^https?:/i.test(node.href)) return node;
                }
                return null;
            };
            globalThis.aeroPeekLink = (x, y, takesClick) => {
                const link = linkAt(x, y);
                if (!link) return null;
                if (takesClick) swallowsClick = true;
                const box = link.getBoundingClientRect();
                return { href: link.href, rect: { x: box.x, y: box.y, width: box.width, height: box.height } };
            };
            addEventListener("click", (event) => {
                if (!swallowsClick) return;
                swallowsClick = false;
                event.preventDefault();
                event.stopImmediatePropagation();
            }, true);
            // A new press starts over: its click is the person's own.
            addEventListener("pointerdown", () => { swallowsClick = false; }, true);
        })();
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: PageScripts.world)

    static let linkAtPoint = "return globalThis.aeroPeekLink?.(x, y, takesClick) ?? null;"
}

extension BrowserPage {
    /// Asks the page for the link under `point`, in the view's points, and the preview the press calls for.
    func handle(_ press: ForcePress, at point: CGPoint) {
        guard let onPeek else { return }
        switch press {
        case .released: return onPeek(.cancel)
        case .pressure(let progress): return onPeek(.pressure(progress))
        case .deep, .forceClick: break
        }
        let scale = webView.pageZoom * webView.magnification
        guard scale > 0 else { return }
        let arguments: [String: Any] = ["x": point.x / scale, "y": point.y / scale, "takesClick": press == .forceClick]
        // The page answers later: a press released, or a new one begun, meanwhile no longer asks for a preview.
        let press = (kind: press, generation: pageView.pressGeneration)
        Task { [weak self] in
            guard let self, let value = try? await webView.callAsyncJavaScript(PeekScripts.linkAtPoint, arguments: arguments, contentWorld: PageScripts.world),
                  pageView.pressGeneration == press.generation, let link = peekLink(from: value) else { return }
            self.onPeek?(press.kind == .forceClick ? .open(link.url, link.origin) : .press(link.url, link.origin))
        }
    }

    /// The page script's answer is untrusted: only a website address within bounds is previewed.
    func peekLink(from value: Any?) -> (url: URL, origin: CGRect?)? {
        guard let body = value as? [String: Any], let href = body["href"] as? String, href.utf8.count <= PeekScripts.maximumAddressLength,
              let url = URL(string: href), NavigationInput.isWebURL(url) else { return nil }
        return (url, viewRect(fromPage: body["rect"]))
    }
}
