// Chrome gives an action popup no tab: `tabs.getCurrent` resolves to nothing there. WebKit returns the tab the
// popup belongs to, and pages that adapt their layout to a tab then do so in the popup.
for (const target of namespaces) {
    const tabs = target.tabs;
    if (typeof tabs?.getCurrent !== "function") continue;
    kept.push(tabs);
    const getCurrent = tabs.getCurrent.bind(tabs);
    Object.defineProperty(tabs, "getCurrent", { configurable: true, value: method(async () => {
        if (await call("tabs/inPopup")) return undefined;
        return await getCurrent();
    }) });
}
