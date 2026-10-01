// Loads before extension worker and page scripts, filling missing WebKit APIs. See docs/EXTENSIONS.md.
(() => {
    "use strict";
    const api = globalThis.browser ?? globalThis.chrome;
    if (!api?.runtime?.id) return;
    const inContentScript = typeof location !== "undefined" && !/^(chrome|webkit)-extension:$/.test(location.protocol);

    const namespaces = [...new Set([globalThis.browser, globalThis.chrome].filter(Boolean))];
    const nativeRuntimes = new Set(namespaces.map((namespace) => namespace.runtime));

    // WebKit recreates unreferenced namespaces without added members. Keep modified objects alive.
    const kept = [...namespaces, ...nativeRuntimes];
    Object.defineProperty(globalThis, Symbol.for("aero.compatibility"), { value: kept });

    // The bridge identifies callers from their context, not the request body. Each request says what the context
    // listens for, so an event its request causes is not lost before the context waits again.
    const call = async (route, body) => {
        const names = listenedEvents();
        const listening = names.length > 0 && route !== "events/next" ? `?listening=${encodeURIComponent(names.join(","))}` : "";
        const response = await fetch(`aero-extension://aero/${route}${listening}`, { method: "POST", body: JSON.stringify(body ?? {}) });
        const reply = await response.json();
        if (!response.ok) throw new Error(reply.error ?? "The request failed.");
        return reply.value;
    };

    // Chrome's methods take a callback or return a promise. WebKit's host getter ignores a JavaScript override of
    // lastError, so during a failed callback the globals expose a runtime that reports it; outside that synchronous
    // call the native bindings are exposed unchanged.
    let callbackError;
    const namespaceWrappers = new WeakMap();
    const exposedNamespace = (namespace) => {
        if (callbackError === undefined || !namespace?.runtime) return namespace;
        if (namespaceWrappers.has(namespace)) return namespaceWrappers.get(namespace);
        const runtime = namespace.runtime;
        const functions = new WeakMap();
        const exposedRuntime = new Proxy(runtime, { get(target, key) {
            if (key === "lastError" && callbackError !== undefined) return callbackError;
            const value = Reflect.get(target, key, target);
            if (typeof value !== "function") return value;
            if (!functions.has(value)) functions.set(value, value.bind(target));
            return functions.get(value);
        } });
        const exposed = new Proxy(namespace, { get(target, key) {
            return key === "runtime" ? exposedRuntime : Reflect.get(target, key, target);
        } });
        namespaceWrappers.set(namespace, exposed);
        return exposed;
    };
    const withLastError = (error, callback) => {
        const previous = callbackError;
        callbackError = { message: String(error?.message ?? error) };
        try { callback(); }
        finally { callbackError = previous; }
    };
    const method = (implementation) => (...args) => {
        const callback = typeof args[args.length - 1] === "function" ? args.pop() : null;
        const result = Promise.resolve().then(() => implementation(...args));
        if (!callback) return result;
        result.then(callback, (error) => withLastError(error, callback));
    };
    const settled = (value) => method(() => value);

    // Chrome's event filters (events.UrlFilter), for the events Aero delivers with a `url`.
    const matchesFilter = (address, filter) => {
        let url;
        try { url = new URL(address); } catch { return false; }
        const host = url.hostname, path = url.pathname, query = url.search.replace(/^\?/, ""), plain = url.href.replace(/#.*$/, "");
        const port = Number(url.port || { "http:": 80, "https:": 443 }[url.protocol] || 0);
        const tests = {
            hostContains: (v) => ("." + host).includes(v), hostEquals: (v) => host === v, hostPrefix: (v) => host.startsWith(v),
            hostSuffix: (v) => host.endsWith(v), pathContains: (v) => path.includes(v), pathEquals: (v) => path === v,
            pathPrefix: (v) => path.startsWith(v), pathSuffix: (v) => path.endsWith(v), queryContains: (v) => query.includes(v),
            queryEquals: (v) => query === v, queryPrefix: (v) => query.startsWith(v), querySuffix: (v) => query.endsWith(v),
            urlContains: (v) => plain.includes(v), urlEquals: (v) => plain === v, urlPrefix: (v) => plain.startsWith(v),
            urlSuffix: (v) => plain.endsWith(v), urlMatches: (v) => new RegExp(v).test(plain),
            originAndPathMatches: (v) => new RegExp(v).test(url.origin + path),
            schemes: (v) => v.includes(url.protocol.slice(0, -1)),
            ports: (v) => v.some((p) => Array.isArray(p) ? port >= p[0] && port <= p[1] : port === p)
        };
        return Object.entries(filter ?? {}).every(([key, value]) => tests[key]?.(value) ?? false);
    };

    // An event that never fires in Aero because what it reports never happens here. docs/EXTENSIONS.md lists them.
    const inertEvent = () => {
        const callbacks = new Set();
        return {
            addListener: listener => callbacks.add(listener), removeListener: listener => callbacks.delete(listener),
            hasListener: listener => callbacks.has(listener), hasListeners: () => callbacks.size > 0
        };
    };
    // An event Aero delivers: while it has listeners, the context waits for Aero's next events. `prepare` may resolve
    // what Aero sends, such as a tab reference, into what Chrome's listeners receive; it returns null to skip one.
    const listeners = new Map();
    const deliveredEvent = (name, prepare = async (values) => values) => {
        // `browser` and `chrome` share each event's listeners.
        if (!listeners.has(name)) listeners.set(name, { entries: new Map(), prepare });
        const { entries } = listeners.get(name);
        return {
            addListener(listener, filter) {
                if (typeof listener !== "function") throw new TypeError("The listener must be a function.");
                entries.set(listener, filter?.url);
                waitForEvents();
            },
            removeListener(listener) { entries.delete(listener); },
            hasListener: (listener) => entries.has(listener),
            hasListeners: () => entries.size > 0
        };
    };
    const listenedEvents = () => [...listeners].filter(([, { entries }]) => entries.size > 0).map(([name]) => name);
    let waiting = false;
    const waitForEvents = () => {
        if (waiting) return;
        waiting = true;
        queueMicrotask(async () => {
            while (listenedEvents().length > 0) {
                let events;
                // Aero refuses a wait only for good, such as for a context it unloads: waiting stops.
                try { events = await call("events/next", { events: listenedEvents() }); }
                catch (error) { console.error(error); break; }
                for (const { name, arguments: received } of events) {
                    const event = listeners.get(name);
                    if (!event) continue;
                    let values;
                    try { values = await event.prepare(received); } catch (error) { console.error(error); continue; }
                    if (!values) continue;
                    for (const [listener, filters] of [...event.entries]) {
                        if (filters && !filters.some((filter) => matchesFilter(values[0]?.url, filter))) continue;
                        try { listener(...values); } catch (error) { console.error(error); }
                    }
                }
            }
            waiting = false;
        });
    };

    const define = (namespace, members) => {
        for (const target of namespaces) {
            const object = target[namespace] ?? (target[namespace] = {});
            kept.push(object);
            for (const [name, make] of Object.entries(members)) {
                if (object[name] == null) Object.defineProperty(object, name, { value: make(), configurable: true, enumerable: true });
            }
        }
    };
    const constants = (values) => () => Object.freeze(Object.fromEntries(values.map((value) => [value.toUpperCase(), value])));
    const absolute = (url) => new URL(url, api.runtime.getURL("/")).href;

    // Aero names a tab by its place: `{ index }` in the main window, or `{ window }`, the index of one of the
    // extension's own windows. Chrome's identifiers are WebKit's, read from its tabs and windows APIs.
    const nativeTab = async (reference) => {
        if (!reference) return { tabId: -1, windowId: -1 };
        const windows = await api.windows.getAll({ populate: true, windowTypes: ["normal", "popup"] });
        const window = reference.window === undefined
            ? windows.find((candidate) => candidate.type === "normal")
            : windows.filter((candidate) => candidate.type === "popup")[reference.window];
        const tab = window?.tabs?.find((candidate) => candidate.index === (reference.index ?? 0));
        return tab ? { tabId: tab.id, windowId: window.id } : { tabId: -1, windowId: -1 };
    };
