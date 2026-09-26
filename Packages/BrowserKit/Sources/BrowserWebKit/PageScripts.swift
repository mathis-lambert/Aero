import BrowserCore
import WebKit

/// Browser-owned scripts run in an isolated world: pages cannot see or tamper with their state.
@MainActor
enum PageScripts {
    static let world = WKContentWorld.world(name: "Aero")

    /// Remembers fields the user typed into, including those inside open shadow roots.
    static let editedFieldTracker = WKUserScript(source: """
        globalThis.aeroEditedFields = new Set();
        document.addEventListener("input", (event) => {
            if (event.isTrusted) globalThis.aeroEditedFields.add(event.composedPath()[0]);
        }, { capture: true, passive: true });
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world)

    /// On the Chrome Web Store, puts Aero's install button in place of the store's grey one. The store's
    /// markup is generated, so nothing leans on its class names: its button is the disabled one naming Chrome. The page never says what to install;
    /// Aero reads that from the tab's address. See docs/EXTENSIONS.md › Installing.
    static let webStoreButton = WKUserScript(source: """
        (() => {
            if (location.hostname !== "chromewebstore.google.com") return;
            const bridge = (body) => window.webkit.messageHandlers.\(webStoreHandlerName).postMessage(body);
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

    static let webStoreHandlerName = "aeroWebStore"

    /// Function body returning whether a field the user edited still holds unsubmitted text.
    static let hasUnsavedInput = """
        const fields = globalThis.aeroEditedFields ?? new Set();
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

    /// The smallest video, in points, worth a picture in picture window: smaller ones are previews or decoration.
    static let minimumPictureInPictureArea = 160 * 90

    /// Function body moving the largest visible, unmuted, playing video of the page to picture in
    /// picture, unless one is there already; returns whether it did.
    static let enterPictureInPicture = """
        const videos = Array.from(document.querySelectorAll("video"));
        if (videos.some((video) => video.webkitPresentationMode !== "inline")) return false;
        const area = (video) => { const box = video.getBoundingClientRect(); return box.width * box.height; };
        const candidates = videos.filter((video) => !video.paused && !video.ended && !video.muted && video.volume > 0
            && video.videoWidth > 0 && area(video) >= \(minimumPictureInPictureArea)
            && video.webkitSupportsPresentationMode?.("picture-in-picture"));
        const video = candidates.sort((a, b) => area(b) - area(a))[0];
        if (!video) return false;
        video.webkitSetPresentationMode("picture-in-picture");
        return true;
        """

    static let exitPictureInPicture = """
        for (const video of document.querySelectorAll("video")) {
            if (video.webkitPresentationMode === "picture-in-picture") video.webkitSetPresentationMode("inline");
        }
        """

    static let isInPictureInPicture = """
        return Array.from(document.querySelectorAll("video")).some((video) => video.webkitPresentationMode === "picture-in-picture");
        """

    static let maximumSelectionLength = 256

    static let selectedText = """
        return getSelection().toString().trim().slice(0, \(maximumSelectionLength));
        """

    static let maximumIconLinks = 32

    /// Function body listing icon declarations; `href` is already resolved against the document base.
    /// Only icon relations are selected, so stylesheets and preloads never crowd icons out of the limit.
    static let declaredIcons = """
        const icons = 'link[href][rel~="icon" i], link[href][rel~="apple-touch-icon" i], link[href][rel~="apple-touch-icon-precomposed" i]';
        return Array.from(document.querySelectorAll(icons), (link) => ({
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
