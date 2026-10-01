// A listener that ignores the message must not steal another listener's response.
chrome.runtime.onMessage.addListener(() => {});
chrome.runtime.onMessage.addListener((message, sender, reply) => {
    if (message.ping) reply("pong");
    if (message.delayed) {
        setTimeout(() => reply("async pong"), 10);
        return true;
    }
    if (message.promised) return Promise.resolve("promised pong");
    if (message.idle) {
        requestIdleCallback((deadline) => reply(typeof deadline.timeRemaining() === "number"));
        return true;
    }
});

// Password managers may wrap the globals after registering listeners. WebKit still needs the native bindings
// there to deliver messages, even when the original objects and their listeners remain alive.
const nativeAPIs = [browser, chrome];
globalThis.browser = new Proxy(browser, { get() {} });
globalThis.chrome = new Proxy(chrome, { get() {} });
// Redefining them, as some extensions install their own getters, must not throw or cut WebKit off either.
Object.defineProperty(globalThis, "browser", { configurable: true, get: () => new Proxy({}, {}) });
globalThis.__defineGetter__("chrome", () => undefined);
