define("search", {
    Disposition: () => Object.freeze({CURRENT_TAB: "CURRENT_TAB", NEW_TAB: "NEW_TAB", NEW_WINDOW: "NEW_WINDOW"}),
    query: () => method(async (details) => {
        if (typeof details?.text !== "string" || (details.tabId !== undefined && details.disposition !== undefined)) {
            throw new Error("Specify search text and either tabId or disposition.");
        }
        const disposition = details.disposition ?? "CURRENT_TAB";
        if (!["CURRENT_TAB", "NEW_TAB", "NEW_WINDOW"].includes(disposition)) throw new Error("Invalid search disposition.");
        const url = await call("search/url", {text: details.text});
        if (details.tabId !== undefined) await api.tabs.update(details.tabId, {url});
        else if (disposition === "NEW_TAB") await api.tabs.create({url, active: true});
        else if (disposition === "NEW_WINDOW") await api.windows.create({url});
        else {
            const [tab] = await api.tabs.query({active: true, currentWindow: true});
            if (!tab) throw new Error("There is no active tab.");
            await api.tabs.update(tab.id, {url});
        }
    })
});
