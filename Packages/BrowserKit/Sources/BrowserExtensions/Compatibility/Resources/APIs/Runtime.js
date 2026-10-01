// Aero applies an extension's update as soon as it is accepted, so it is never left waiting for a restart.
const filterOn = (filter, key) => Array.isArray(filter?.[key]) ? new Set(filter[key].map(String)) : null;
define("runtime", {
    onUpdateAvailable: inertEvent,
    onRestartRequired: inertEvent,
    getContexts: () => method(async (filter = {}) => {
        if (typeof filter !== "object" || filter === null || Array.isArray(filter)) throw new Error("Invalid context filter.");
        const found = await call("runtime/contexts", filter);
        const tabIds = filterOn(filter, "tabIds"), windowIds = filterOn(filter, "windowIds"), documentIds = filterOn(filter, "documentIds");
        const contexts = [];
        for (const { tab, ...context } of found) {
            if (tab) Object.assign(context, await nativeTab(tab));
            if (tabIds && !tabIds.has(String(context.tabId))) continue;
            if (windowIds && !windowIds.has(String(context.windowId))) continue;
            if (documentIds) continue;
            contexts.push(context);
        }
        return contexts;
    }),
    ContextType: () => Object.freeze({ TAB: "TAB", POPUP: "POPUP", BACKGROUND: "BACKGROUND", OFFSCREEN_DOCUMENT: "OFFSCREEN_DOCUMENT", SIDE_PANEL: "SIDE_PANEL", DEVELOPER_TOOLS: "DEVELOPER_TOOLS" })
});
