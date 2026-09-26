// Sets its badge only if the inert declarations came first: WebKit has no onHistoryStateUpdated.
chrome.webNavigation.onHistoryStateUpdated.addListener(() => {});
chrome.action.setBadgeText({ text: "ok" });
