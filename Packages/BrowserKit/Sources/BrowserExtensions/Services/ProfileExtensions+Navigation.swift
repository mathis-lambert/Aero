import BrowserCore
import Foundation
import WebKit

extension ProfileExtensions {
    /// `webNavigation` events WebKit does not deliver, for the main frame of the profile's tabs, to extensions that may
    /// read the page, as for WebKit's own events. The layer resolves each tab's place into WebKit's identifiers.
    public func didNavigateWithinDocument(_ tabID: UUID, to url: URL, from previous: URL?, transition: HistoryTransition) {
        guard let index = host?.tabIDs(inProfile: profileID).firstIndex(of: tabID) else { return }
        let fragmentOnly = previous.map { Self.withoutFragment($0) == Self.withoutFragment(url) } == true
        let details: [String: Any] = [
            "tab": ["index": index], "url": url.absoluteString, "frameId": 0, "parentFrameId": -1, "processId": -1,
            "transitionType": transition.rawValue, "transitionQualifiers": [String](),
            "documentLifecycle": "active", "frameType": "outermost_frame", "timeStamp": Date.now.timeIntervalSince1970 * 1000
        ]
        let name = fragmentOnly ? "webNavigation.onReferenceFragmentUpdated" : "webNavigation.onHistoryStateUpdated"
        let tab = tab(tabID)
        for (id, context) in contexts where context.hasPermission(.webNavigation, in: tab) && context.hasAccess(to: url, in: tab) {
            deliver(name, [details], to: id)
        }
    }

    /// A page of one of the profile's tabs opened another, with `window.open` or a link to a new window.
    public func didOpenNavigationTarget(_ tabID: UUID, from sourceTabID: UUID) {
        let tabIDs = host?.tabIDs(inProfile: profileID) ?? []
        guard let index = tabIDs.firstIndex(of: tabID), let source = tabIDs.firstIndex(of: sourceTabID), let url = host?.tab(tabID)?.url else { return }
        let details: [String: Any] = [
            "tab": ["index": index], "sourceTab": ["index": source], "sourceFrameId": 0, "sourceProcessId": -1,
            "url": url.absoluteString, "timeStamp": Date.now.timeIntervalSince1970 * 1000
        ]
        let sourceTab = tab(sourceTabID)
        for (id, context) in contexts where context.hasPermission(.webNavigation, in: sourceTab) && context.hasAccess(to: url, in: tab(tabID)) {
            deliver("webNavigation.onCreatedNavigationTarget", [details], to: id)
        }
    }

    private static func withoutFragment(_ url: URL) -> String {
        url.absoluteString.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? url.absoluteString
    }
}
