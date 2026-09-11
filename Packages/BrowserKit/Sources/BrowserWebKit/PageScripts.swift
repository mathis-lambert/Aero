import WebKit

/// Browser-owned scripts run in an isolated world: pages cannot see or tamper with their state.
@MainActor
enum PageScripts {
    static let world = WKContentWorld.world(name: "LightBrowser")

    /// Remembers fields the user typed into, including those inside open shadow roots.
    static let editedFieldTracker = WKUserScript(source: """
        globalThis.lightBrowserEditedFields = new Set();
        document.addEventListener("input", (event) => {
            if (event.isTrusted) globalThis.lightBrowserEditedFields.add(event.composedPath()[0]);
        }, { capture: true, passive: true });
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world)

    /// Function body returning whether a field the user edited still holds unsubmitted text.
    static let hasUnsavedInput = """
        const fields = globalThis.lightBrowserEditedFields ?? new Set();
        for (const field of fields) {
            if (!field.isConnected) { fields.delete(field); continue; }
            const text = field.isContentEditable ? field.textContent : field.value;
            if (typeof text === "string" && text.trim() !== "" && text !== field.defaultValue) return true;
        }
        return false;
        """
}
