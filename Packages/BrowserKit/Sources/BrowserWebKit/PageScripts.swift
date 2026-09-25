import BrowserCore
import WebKit

/// Browser-owned scripts run in an isolated world: pages cannot see or tamper with their state.
@MainActor
enum PageScripts {
    static let world = WKContentWorld.world(name: "Auro")

    /// Remembers fields the user typed into, including those inside open shadow roots.
    static let editedFieldTracker = WKUserScript(source: """
        globalThis.auroEditedFields = new Set();
        document.addEventListener("input", (event) => {
            if (event.isTrusted) globalThis.auroEditedFields.add(event.composedPath()[0]);
        }, { capture: true, passive: true });
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world)

    /// Function body returning whether a field the user edited still holds unsubmitted text.
    static let hasUnsavedInput = """
        const fields = globalThis.auroEditedFields ?? new Set();
        for (const field of fields) {
            if (!field.isConnected) { fields.delete(field); continue; }
            const text = field.isContentEditable ? field.textContent : field.value;
            if (typeof text === "string" && text.trim() !== "" && text !== field.defaultValue) return true;
        }
        return false;
        """

    /// Function body resolving after the committed document has produced a frame.
    static let nextFrame = """
        await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
        return true;
        """

    static let maximumIconLinks = 32

    /// Function body listing link declarations; `href` is already resolved against the document base.
    static let declaredIcons = """
        return Array.from(document.querySelectorAll("link[rel][href]"), (link) => ({
            rel: link.rel, href: link.href, sizes: link.getAttribute("sizes"), type: link.type
        })).slice(0, \(maximumIconLinks));
        """

    /// Page scripts are untrusted: keep only well-formed, bounded string fields.
    static func iconLinks(from result: Any?) -> [FaviconLink] {
        guard let entries = result as? [Any] else { return [] }
        return entries.prefix(maximumIconLinks).compactMap { entry in
            guard let fields = entry as? [String: Any],
                  let rel = bounded(fields["rel"]), let href = bounded(fields["href"]) else { return nil }
            return FaviconLink(rel: rel, href: href, sizes: bounded(fields["sizes"]), type: bounded(fields["type"]))
        }
    }

    private static func bounded(_ value: Any?) -> String? {
        guard let string = value as? String, string.count <= FaviconCandidate.maximumURLLength else { return nil }
        return string
    }
}
