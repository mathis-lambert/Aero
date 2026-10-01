// Sets its badge only if the compatibility layer came first (WebKit has no onHistoryStateUpdated) and
// the native host echoed its message back.
chrome.webNavigation.onHistoryStateUpdated.addListener(() => {});
const port = chrome.runtime.connectNative("app.getaero.test.echo");
port.onMessage.addListener((message) => chrome.action.setBadgeText({ text: message.badge }));
port.postMessage({ badge: "ok" });
chrome.runtime.onMessage.addListener(message => Promise.resolve({received: message.fixture}));
