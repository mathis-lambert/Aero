import Foundation
import JavaScriptCore
import Testing
@testable import BrowserExtensions

// The compatibility layer in JavaScriptCore, with a stand-in for WebKit's `chrome` and for Aero's scheme: every
// request is recorded, and each route answers what the test sets. Failure modes: an addition that replaces WebKit's
// own API, one lost from `browser` or `chrome`, a namespace left unreferenced, a request that names the wrong route or
// forgets its arguments, a callback never called, permissions Aero provides answered by WebKit, and intercepted
// property definitions that apply non-enumerable descriptors or mutate objects before validating all descriptors.

@Test func additionsFillOnlyWhatWebKitLacks() throws {
    let harness = try CompatibilityHarness(api: "{ webNavigation: { onCompleted: { addListener() { globalThis.nativeUsed = true; } } } }")
    harness.run("chrome.webNavigation.onCompleted.addListener(() => {}); chrome.webNavigation.onHistoryStateUpdated.addListener(() => {});")
    #expect(harness.bool("globalThis.nativeUsed === true"), "WebKit's own API is kept")
    #expect(harness.string("typeof chrome.webNavigation.onCreatedNavigationTarget.addListener") == "function")
    #expect(harness.string("typeof chrome.runtime.onUpdateAvailable.addListener") == "function")
    #expect(harness.string("typeof chrome.storage.managed.get") == "function")
    #expect(harness.string("typeof chrome.offscreen.createDocument") == "function")
}

@Test func bothNamespacesGetTheAdditionsAndStayReferenced() throws {
    let harness = try CompatibilityHarness(prelude: "globalThis.browser = { runtime: chrome.runtime };")
    #expect(harness.string("typeof browser.idle.queryState") == "function")
    #expect(harness.string("typeof chrome.idle.queryState") == "function")
    #expect(harness.bool("globalThis[Symbol.for('aero.compatibility')].includes(chrome.runtime)"),
            "WebKit would rebuild an unreferenced namespace without the additions")
}

@Test func replacingAGlobalCannotDisconnectItsNativeAPI() throws {
    let harness = try CompatibilityHarness(prelude: "globalThis.browser = { runtime: chrome.runtime };")
    harness.run("""
        const originalBrowser = browser;
        const originalChrome = chrome;
        globalThis.browser = new Proxy(browser, { get() {} });
        globalThis.chrome = new Proxy(chrome, { get() {} });
        globalThis.bindingsIntact = browser === originalBrowser && chrome === originalChrome;
        """)
    #expect(harness.bool("globalThis.bindingsIntact"))
}

@Test func aPolyfillCanReplaceAGlobalWithoutHidingTheNativeRuntime() throws {
    let harness = try CompatibilityHarness(prelude: "globalThis.browser = {runtime: chrome.runtime};")
    harness.run("globalThis.browser = {...browser, polyfilled: true};")
    #expect(harness.bool("browser.polyfilled === true"))
    #expect(harness.bool("browser.runtime.id === chrome.runtime.id"))
}

@Test func aReplacementThatLaterHidesTheRuntimeFallsBackToTheNativeNamespace() throws {
    let harness = try CompatibilityHarness()
    harness.run("""
        const native = chrome;
        let hidden = false;
        globalThis.chrome = new Proxy(native, { get: (target, key) => hidden ? undefined : Reflect.get(target, key) });
        globalThis.replaced = chrome !== native;
        hidden = true;
        globalThis.restored = chrome === native;
        """)
    #expect(harness.bool("globalThis.replaced && globalThis.restored"))
}

@Test func redefiningAGlobalNeitherThrowsNorHidesTheNativeNamespace() throws {
    let harness = try CompatibilityHarness(prelude: "globalThis.browser = { runtime: chrome.runtime };")
    harness.run("""
        const nativeBrowser = browser, nativeChrome = chrome;
        Object.defineProperty(globalThis, "browser", { configurable: true, get: () => ({ runtime: nativeChrome.runtime, fromGetter: true }) });
        globalThis.__defineGetter__("chrome", () => ({}));
        Reflect.defineProperty(globalThis, "chrome", { value: 1 });
        globalThis.results = [browser.fromGetter === true, chrome === nativeChrome,
            Object.getOwnPropertyDescriptor(globalThis, "browser").configurable === false];
        // Other definitions are left as they are.
        Object.defineProperty(globalThis, "other", { value: 2 });
        globalThis.results.push(globalThis.other === 2);
        """)
    #expect(harness.string("JSON.stringify(results)") == "[true,true,true,true]")
}

@Test func ordinaryPropertyDefinitionsKeepNativeFailureAndEnumerationBehavior() throws {
    let harness = try CompatibilityHarness()
    harness.run("""
        const descriptors = {};
        Object.defineProperty(descriptors, "hidden", { value: { value: 42 }, enumerable: false });
        const target = {};
        Object.defineProperties(target, descriptors);
        const partial = {};
        let refused = false;
        try { Object.defineProperties(partial, { first: { value: 1 }, invalid: { get: 123 } }); }
        catch (error) { refused = error instanceof TypeError; }
        globalThis.results = [!Object.hasOwn(target, "hidden"), refused, !Object.hasOwn(partial, "first")];
        """)
    #expect(harness.string("JSON.stringify(results)") == "[true,true,true]")
}

@Test func batchGlobalDefinitionsPreserveNativePropertiesAndValidateReplacements() throws {
    let harness = try CompatibilityHarness()
    harness.run("""
        const runtime = chrome.runtime;
        const definitions = {};
        Object.defineProperty(definitions, "ignored", { value: { value: 1 }, enumerable: false });
        definitions.chrome = { value: { runtime, polyfilled: true } };
        Object.defineProperty(globalThis, "existing", { value: 1, writable: true, configurable: true });
        definitions.existing = { value: 2 };
        Object.defineProperties(globalThis, definitions);
        let refused = false;
        try { Object.defineProperties(globalThis, { chrome: { value: { runtime, changed: true } }, invalid: { get: 123 } }); }
        catch (error) { refused = error instanceof TypeError; }
        const existing = Object.getOwnPropertyDescriptor(globalThis, "existing");
        globalThis.results = [chrome.polyfilled === true, !Object.hasOwn(globalThis, "ignored"),
            existing.value === 2 && existing.writable && existing.configurable, refused, chrome.changed === undefined];
        """)
    #expect(harness.string("JSON.stringify(results)") == "[true,true,true,true,true]")
}

@Test func passwordSavingIsAChromeSettingOfTheProfile() throws {
    let harness = try CompatibilityHarness()
    harness.run("""
        replies["privacy/passwordSaving"] = { value: true, levelOfControl: "controllable_by_this_extension" };
        chrome.privacy.services.passwordSavingEnabled.set({ value: false });
        chrome.privacy.services.passwordSavingEnabled.set({ value: "no" }).catch((error) => { globalThis.refused = error.message; });
        chrome.privacy.services.autofillCreditCardEnabled.set({ value: true }).catch(() => { globalThis.fixed = true; });
        chrome.privacy.services.passwordSavingEnabled.get({}, (setting) => { globalThis.control = setting.levelOfControl; });
        """)
    #expect(harness.requests.contains(#"{"route":"privacy/setPasswordSaving","body":{"value":false}}"#))
    #expect(harness.string("globalThis.refused") == "The value must be a boolean.")
    #expect(harness.bool("globalThis.fixed === true"), "Aero fills no cards: that setting is not controllable")
    #expect(harness.string("globalThis.control") == "controllable_by_this_extension")
}

@Test func idleCallbacksRunInDocuments() throws {
    let harness = try CompatibilityHarness(prelude: """
        globalThis.document = {};
        globalThis.performance = { now: () => 0 };
        globalThis.timers = [];
        globalThis.setTimeout = (callback) => timers.push(callback);
        globalThis.clearTimeout = () => {};
        """)
    harness.run("requestIdleCallback((deadline) => { globalThis.remaining = deadline.timeRemaining(); }); timers.forEach((timer) => timer());")
    #expect(harness.string("String(globalThis.remaining)") == "50")
}

@Test func contextsInTabsCarryWebKitsIdentifiers() async throws {
    let harness = try CompatibilityHarness(api: """
        { windows: { getAll: async () => [
            { id: 7, type: "normal", tabs: [{ id: 70, index: 0 }, { id: 71, index: 1 }] },
            { id: 8, type: "popup", tabs: [{ id: 80, index: 0 }] }] } }
        """)
    harness.run("""
        replies["runtime/contexts"] = [
            { contextType: "BACKGROUND", contextId: "b", tabId: -1, windowId: -1 },
            { contextType: "TAB", contextId: "t", tabId: -1, windowId: -1, tab: { index: 1 } },
            { contextType: "TAB", contextId: "w", tabId: -1, windowId: -1, tab: { window: 0, index: 0 } }];
        chrome.runtime.getContexts({}).then((contexts) => { globalThis.all = contexts; });
        chrome.runtime.getContexts({ tabIds: [80] }).then((contexts) => { globalThis.window = contexts; });
        """)
    let deadline = ContinuousClock.now + .seconds(2)
    while !harness.bool("globalThis.window !== undefined"), ContinuousClock.now < deadline { await Task.yield() }
    #expect(harness.string("JSON.stringify(all.map((c) => [c.contextId, c.tabId, c.windowId]))") == #"[["b",-1,-1],["t",71,7],["w",80,8]]"#)
    #expect(harness.string("JSON.stringify(window.map((c) => c.contextId))") == #"["w"]"#)
    #expect(harness.bool("all.every((c) => c.tab === undefined)"), "Aero's tab reference stays internal")
}

@Test func navigationEventsResolveTheirTabsAndFilters() async throws {
    let harness = try CompatibilityHarness(api: """
        { windows: { getAll: async () => [{ id: 7, type: "normal", tabs: [{ id: 70, index: 0 }] }] } }
        """)
    harness.run("""
        let answered = false;
        globalThis.fetch = async (url, init) => {
            // Later waits stay open, as Aero's do until the next event.
            if (answered) return new Promise(() => {});
            answered = true;
            const details = (address) => ({ tab: { index: 0 }, url: address, frameId: 0, transitionType: "link" });
            return { ok: true, json: async () => ({ value: [
                { name: "webNavigation.onHistoryStateUpdated", arguments: [details("https://example.com/a")] },
                { name: "webNavigation.onHistoryStateUpdated", arguments: [details("https://other.example/b")] }] }) };
        };
        globalThis.heard = [];
        chrome.webNavigation.onHistoryStateUpdated.addListener((details) => {
            heard.push([details.tabId, details.url, details.tab === undefined]);
        }, { url: [{ hostEquals: "example.com" }] });
        """)
    let deadline = ContinuousClock.now + .seconds(2)
    while !harness.bool("heard.length > 0"), ContinuousClock.now < deadline { await Task.yield() }
    #expect(harness.string("JSON.stringify(heard)") == #"[[70,"https://example.com/a",true]]"#)
}

@Test func contentScriptsKeepTheirNativeAPIsWithoutPrivilegedAdditions() throws {
    let harness = try CompatibilityHarness(prelude: "globalThis.location = {protocol: 'https:'};")
    #expect(harness.bool("chrome.offscreen === undefined && chrome.downloads === undefined && chrome.management === undefined"))
    #expect(harness.bool("chrome.runtime.id.length === 32"))
}

@Test func nothingIsAddedOutsideAnExtension() throws {
    let context = try #require(JSContext())
    context.evaluateScript("globalThis.chrome = { runtime: {} };")
    context.evaluateScript(try String(decoding: ExtensionCompatibility.script(), as: UTF8.self))
    #expect(context.evaluateScript("chrome.offscreen === undefined").toBool())
}

@Test func requestsNameTheirRouteAndArguments() throws {
    let harness = try CompatibilityHarness()
    harness.run("""
        replies["offscreen/has"] = true;
        replies["idle/state"] = "idle";
        chrome.offscreen.createDocument({ url: "offscreen.html", reasons: ["CLIPBOARD"], justification: "copy" });
        chrome.offscreen.hasDocument().then((value) => { globalThis.hasDocument = value; });
        chrome.idle.queryState(30, (state) => { globalThis.state = state; });
        chrome.notifications.create("n1", { title: "T", message: "M" });
        chrome.notifications.create({ title: "Untitled" });
        """)
    let requests = harness.requests
    #expect(requests.contains(#"{"route":"offscreen/create","body":{"url":"webkit-extension://base/offscreen.html","reasons":["CLIPBOARD"],"justification":"copy"}}"#),
            "A relative document address is the extension's own")
    #expect(requests.contains(#"{"route":"idle/state","body":{"interval":30}}"#))
    #expect(requests.contains(#"{"route":"notifications/create","body":{"id":"n1","options":{"title":"T","message":"M"}}}"#))
    #expect(requests.contains(#"{"route":"notifications/create","body":{"id":"","options":{"title":"Untitled"}}}"#))
    #expect(harness.bool("globalThis.hasDocument === true"))
    #expect(harness.string("globalThis.state") == "idle", "A callback gets the answer")
}

@Test func aRefusalRejectsThePromiseAndStillCallsTheCallback() throws {
    let harness = try CompatibilityHarness()
    harness.run("""
        replies["idle/state"] = { failure: "The extension was not granted the idle permission." };
        chrome.idle.queryState(60).catch((error) => { globalThis.message = error.message; });
        const log = console?.error;
        globalThis.console = { error() {} };
        chrome.idle.queryState(60, (state) => {
            globalThis.called = state === undefined;
            globalThis.callbackError = chrome.runtime.lastError?.message;
        });
        """)
    #expect(harness.string("globalThis.message") == "The extension was not granted the idle permission.")
    #expect(harness.bool("globalThis.called"))
    #expect(harness.string("globalThis.callbackError") == "The extension was not granted the idle permission.")
    #expect(harness.bool("chrome.runtime.lastError === undefined"), "Callback errors end with the callback")
}

@Test func deliveredEventsReachTheirListeners() throws {
    let harness = try CompatibilityHarness()
    harness.run("""
        let answered = false;
        globalThis.fetch = async (url, init) => {
            const route = url.replace("aero-extension://aero/", "");
            requests.push({ route, body: JSON.parse(init.body) });
            if (answered) { chrome.idle.onStateChanged.removeListener(listener); return { ok: true, json: async () => ({ value: [] }) }; }
            answered = true;
            return { ok: true, json: async () => ({ value: [{ name: "idle.onStateChanged", arguments: ["locked"] }] }) };
        };
        const listener = (state) => { globalThis.received = state; };
        chrome.idle.onStateChanged.addListener(listener);
        """)
    #expect(harness.string("globalThis.received") == "locked")
    #expect(harness.requests.contains(#"{"route":"events/next","body":{"events":["idle.onStateChanged"]}}"#), "The wait says what the context listens for")
    #expect(harness.bool("!chrome.idle.onStateChanged.hasListeners()"))
}

@Test func providedPermissionsAreAnsweredByAeroAndTheRestByWebKit() throws {
    let harness = try CompatibilityHarness(manifest: #"{"permissions": ["storage"], "optional_permissions": ["idle"]}"#, api: """
        { permissions: {
            contains: async (query) => { globalThis.webKitAsked = query; return true; },
            getAll: async () => ({ permissions: ["storage"], origins: [] }),
            request: async (query) => { globalThis.webKitRequested = query; return true; },
            remove: async () => true } }
        """)
    harness.run("""
        replies["permissions/provided"] = [];
        replies["permissions/request"] = true;
        chrome.permissions.contains({ permissions: ["idle"] }).then((value) => { globalThis.hasIdle = value; });
        chrome.permissions.contains({ permissions: ["storage"] }).then((value) => { globalThis.hasStorage = value; });
        chrome.permissions.request({ permissions: ["idle", "tabs"], origins: ["https://example.com/*"] }).then((value) => { globalThis.requested = value; });
        chrome.permissions.request({ permissions: ["tabs"] }).then((value) => { globalThis.nativeRequested = value; });
        """)
    #expect(harness.bool("globalThis.hasIdle === false"), "Not granted yet: Aero says so without WebKit")
    #expect(harness.bool("globalThis.hasStorage === true"))
    #expect(harness.string("JSON.stringify(globalThis.webKitAsked)") == #"{"permissions":["storage"]}"#)
    #expect(harness.requests.contains(#"{"route":"permissions/request","body":{"permissions":["idle","tabs"],"origins":["https://example.com/*"]}}"#),
            "A request naming one of Aero's permissions is asked once, whole")
    #expect(harness.string("JSON.stringify(globalThis.webKitRequested)") == #"{"permissions":["tabs"]}"#, "WebKit keeps requests that are all its own")
    #expect(harness.bool("globalThis.requested === true && globalThis.nativeRequested === true"))
}

@Test func unsupportedPermissionsAndExtensionOriginsAreRefused() async throws {
    let harness = try CompatibilityHarness(api: "{ permissions: { contains: async () => { globalThis.askedWebKit=true; return true; }, getAll: async () => ({}), request: async () => true, remove: async () => true } }")
    harness.run("Promise.all([chrome.permissions.contains({permissions:['proxy']}), chrome.permissions.contains({origins:['chrome-extension://bbbb/*']}), chrome.permissions.request({permissions:['unknown']})]).then(values=>globalThis.refused=values)")
    let deadline = ContinuousClock.now + .seconds(2)
    while !harness.bool("globalThis.refused !== undefined"), ContinuousClock.now < deadline { await Task.yield() }
    #expect(harness.string("JSON.stringify(refused)") == "[false,false,false]")
    #expect(!harness.bool("globalThis.askedWebKit === true"))
}

// MARK: - Packages prepared by an earlier Aero

@Test func anOutdatedLayerIsReplacedAndACurrentOneLeftAlone() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("aero-refresh-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try Data(#"{"manifest_version":3,"name":"Fixture","version":"1"}"#.utf8).write(to: folder.appendingPathComponent("manifest.json"))
    let file = folder.appendingPathComponent(ExtensionPackage.compatibilityFile)
    try Data("// an earlier layer".utf8).write(to: file)
    try ExtensionPackage.refreshCompatibility(in: folder)
    #expect(try Data(contentsOf: file) == ExtensionCompatibility.script())
    let written = try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date
    try ExtensionPackage.refreshCompatibility(in: folder)
    #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date == written, "An up-to-date layer is not rewritten")
}
