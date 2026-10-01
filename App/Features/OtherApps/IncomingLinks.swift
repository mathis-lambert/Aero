import BrowserCore
import Foundation

/// Web addresses other apps open with Aero, as the default browser or by name. See docs/OTHER_APPS.md › Links from
/// other apps.
extension BrowserModel {
    /// Only web addresses are kept: another app cannot make Aero open a local file or one of its own pages. The main
    /// window comes forward even while a link waits, so the onboarding or import holding it is what the person sees.
    func openFromOtherApp(_ urls: [URL]) {
        let links = urls.filter { NavigationInput.isWebURL($0) || NavigationInput.isLocalFileURL($0) }
        guard !links.isEmpty else { return }
        pendingLinks += links
        openPendingLinks()
        // While records load, startup opens the window itself.
        if startup != .loading { showMainWindow() }
    }

    /// Each link opens in a new tab of the selected space, the last one selected, once records are loaded, no
    /// onboarding or import covers the browser and no structural change is being saved; until then they wait.
    func openPendingLinks() {
        guard !pendingLinks.isEmpty, isReady, onboarding == nil, !isChangingStructure, let spaceID = space?.id else { return }
        let links = pendingLinks
        pendingLinks = []
        let opened = links.compactMap { addTab($0, in: spaceID) }
        guard let last = opened.last else { return }
        window.controlBar = nil
        selectTab(last.id)
    }
}
