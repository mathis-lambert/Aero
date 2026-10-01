// Sets its badge only if the compatibility layer came first (WebKit has no onHistoryStateUpdated) and
// the native host echoed its message back.
chrome.webNavigation.onHistoryStateUpdated.addListener(() => {});
const port = chrome.runtime.connectNative("app.getaero.test.echo");
port.onMessage.addListener((message) => chrome.action.setBadgeText({ text: message.badge }));
port.postMessage({ badge: "ok" });
chrome.runtime.onMessage.addListener(message => Promise.resolve({received: message.fixture}));
// An item of the extension's own on its button, which Aero shows before its items.
chrome.contextMenus.create({ id: "fixture", title: "Fixture action item", contexts: ["action"] }, () => void chrome.runtime.lastError);
