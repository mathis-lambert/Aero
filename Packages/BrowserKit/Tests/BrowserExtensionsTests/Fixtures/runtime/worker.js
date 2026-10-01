// A worker's globals replaced by getters that keep WebKit's runtime: scripts read the replacement, WebKit still delivers.
const nativeChrome = chrome;
Object.defineProperty(globalThis, "chrome", { configurable: true, get: () => new Proxy(nativeChrome, {
    get: (target, key) => key === "replaced" ? true : Reflect.get(target, key)
}) });

// Each check names what failed; the button's title becomes "ok" once all pass.
const failures = [];
const check = async (name, test) => {
    try { if (!(await test())) failures.push(name); }
    catch (error) { failures.push(`${name}: ${error.message}`); }
};
const pause = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));

(async () => {
    // WebKit rebuilds namespaces nothing references, which would drop Aero's additions: allocate until it collects.
    for (let round = 0; round < 50; round += 1) new Array(200000).fill(round);
    await pause(100);
    await check("replaced global", () => chrome.replaced === true && chrome.runtime.id.length === 32);
    await check("kept", () => typeof chrome.runtime.onUpdateAvailable?.addListener === "function"
        && typeof browser.webNavigation.onHistoryStateUpdated?.addListener === "function");
    await check("self", async () => (await chrome.management.getSelf()).installType === "development");
    await check("idle", async () => ["active", "idle", "locked"].includes(await chrome.idle.queryState(60)));
    await check("permissions", async () => await chrome.permissions.contains({ permissions: ["idle", "storage"] }));
    await check("offscreen", async () => {
        await chrome.offscreen.createDocument({ url: "offscreen.html", reasons: ["DOM_PARSER"], justification: "test" });
        return await chrome.offscreen.hasDocument();
    });
    await check("offscreen replies", async () => {
        for (let attempt = 0; attempt < 50; attempt += 1) {
            try { if (await chrome.runtime.sendMessage({ ping: true }) === "pong") return true; } catch {}
            await pause(100);
        }
        return false;
    });
    await check("idle callback", async () => await chrome.runtime.sendMessage({ idle: true }) === true);
    await check("asynchronous reply", async () => await chrome.runtime.sendMessage({ delayed: true }) === "async pong");
    await check("promised reply", async () => await chrome.runtime.sendMessage({ promised: true }) === "promised pong");
    await check("contexts", async () => {
        const contexts = await chrome.runtime.getContexts({});
        const offscreen = await chrome.runtime.getContexts({ contextTypes: ["OFFSCREEN_DOCUMENT"] });
        return contexts.some((context) => context.contextType === "BACKGROUND") && offscreen.length === 1
            && offscreen[0].documentUrl.endsWith("/offscreen.html");
    });
    await check("single offscreen", async () => {
        try { await chrome.offscreen.createDocument({ url: "offscreen.html", reasons: ["DOM_PARSER"], justification: "again" }); return false; }
        catch { return true; }
    });
    await check("closed", async () => {
        await chrome.offscreen.closeDocument();
        return !(await chrome.offscreen.hasDocument());
    });
    await check("refused", async () => {
        try { await chrome.notifications.create({ title: "Not granted" }); return false; }
        catch (error) { return error.message.includes("notifications"); }
    });
    await check("callback refusal", () => new Promise(resolve => {
        chrome.notifications.create({ title: "Not granted" }, () => {
            const message = chrome.runtime.lastError?.message;
            queueMicrotask(() => {
                const cleared = chrome.runtime.lastError;
                resolve(message?.includes("notifications") && cleared == null);
            });
        });
    }));
    // One request for an Aero permission and a WebKit one: asked once, granted together.
    const added = new Promise((resolve) => chrome.permissions.onAdded.addListener((permissions) => {
        if (permissions.permissions.includes("notifications")) resolve(true);
    }));
    await check("combined request", async () => await chrome.permissions.request({ permissions: ["notifications", "tabs"] })
        && await chrome.permissions.contains({ permissions: ["notifications", "tabs"] }));
    await check("added event", () => Promise.race([added, pause(5000).then(() => false)]));
    await check("permission level", async () => await chrome.notifications.getPermissionLevel() === "granted");
    await check("undeclared", async () => {
        try { await chrome.permissions.request({ permissions: ["history"] }); return false; }
        catch (error) { return error.message.includes("manifest"); }
    });
    await check("password saving", async () => {
        const saving = chrome.privacy.services.passwordSavingEnabled;
        if ((await saving.get({})).levelOfControl !== "controllable_by_this_extension") return false;
        await saving.set({ value: false });
        const taken = await saving.get({});
        await saving.set({ value: true });
        const given = await saving.get({});
        return taken.value === false && taken.levelOfControl === "controlled_by_this_extension"
            && given.levelOfControl === "controllable_by_this_extension"
            && (await chrome.privacy.services.autofillAddressEnabled.get({})).levelOfControl === "not_controllable";
    });
    await check("inventory", async () => (await chrome.management.getAll()).some((item) => item.id === chrome.runtime.id && item.enabled));
    await check("removed", async () => await chrome.permissions.remove({ permissions: ["notifications"] })
        && !(await chrome.permissions.contains({ permissions: ["notifications"] })));
    chrome.action.setTitle({ title: failures.length > 0 ? failures.join("; ") : "ok" });
})();
