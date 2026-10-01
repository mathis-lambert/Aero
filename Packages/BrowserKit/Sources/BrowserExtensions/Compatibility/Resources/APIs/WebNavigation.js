// Events WebKit does not deliver, from what Aero observes of its tabs' main frames. Aero never swaps one tab's page
// for another tab's, so onTabReplaced never fires.
const navigation = (name) => () => deliveredEvent(`webNavigation.${name}`, async ([details]) => {
    const { tabId } = await nativeTab(details.tab);
    if (tabId === -1) return null;
    const { tab, sourceTab, ...rest } = details;
    const resolved = { ...rest, tabId, timeStamp: rest.timeStamp ?? Date.now() };
    if (sourceTab) {
        resolved.sourceTabId = (await nativeTab(sourceTab)).tabId;
        if (resolved.sourceTabId === -1) return null;
    }
    return [resolved];
});
define("webNavigation", {
    onHistoryStateUpdated: navigation("onHistoryStateUpdated"),
    onReferenceFragmentUpdated: navigation("onReferenceFragmentUpdated"),
    onCreatedNavigationTarget: navigation("onCreatedNavigationTarget"),
    onTabReplaced: inertEvent
});
