import AppKit
import BrowserCore
import BrowserWebKit

/// A link previewed over its tab (docs/BROWSING.md › Peek): a live page outside any tab, until it closes or becomes a
/// tab of its own. One per window, which ends as soon as another tab is shown.
struct Peek: Identifiable {
    enum Phase {
        /// Following a press on the link, its page loading: it shows as far as the press has gone.
        case pressing
        case open
        /// Shrinking back into its link before its page ends.
        case closing
        /// Growing over the whole page before it becomes a tab.
        case expanding
    }

    let id = UUID()
    let url: URL
    let page: BrowserPage
    let openerTabID: UUID
    /// The link's frame in the opener's page, in points, which the preview grows out of and returns to.
    let origin: CGRect?
    var phase: Phase
}

extension BrowserModel {
    func page(_ tabID: UUID, peek request: PeekRequest) {
        switch request {
        case .press(let url, let origin):
            // Released before the page answered: nothing would end the press.
            guard NSEvent.pressedMouseButtons & 1 != 0 else { return }
            startPeek(url, from: tabID, origin: origin, phase: .pressing)
        case .pressure(let progress):
            if window.peek?.phase == .pressing { window.peekPressure = min(max(progress, 0), 1) }
        case .open(let url, let origin):
            if let peek = window.peek, peek.phase == .pressing, peek.url == url, peek.openerTabID == tabID { window.peek?.phase = .open }
            else { startPeek(url, from: tabID, origin: origin, phase: .open) }
        case .cancel:
            if window.peek?.phase == .pressing { window.peek?.phase = .closing }
        }
    }

    /// Asks the preview to leave; its view ends it once it has shrunk away (`endPeek`).
    func dismissPeek() {
        guard window.peek?.phase == .open || window.peek?.phase == .pressing else { return }
        window.peek?.phase = .closing
    }

    /// Asks the preview to become a tab; its view does so once it has grown over the page (`adoptPeek`).
    func openPeekInTab() {
        guard window.peek?.phase == .open else { return }
        window.peek?.phase = .expanding
    }

    /// Ends the preview and its page at once; `id` names the one a late animation meant.
    func endPeek(_ id: Peek.ID? = nil) {
        guard let peek = window.peek, id == nil || id == peek.id else { return }
        window.peek = nil
        resetPeekPresentation()
        pages.discardDetachedPage(peek.page)
    }

    /// The preview's page becomes a tab after its opener, shown at once, without reloading.
    func adoptPeek(_ id: Peek.ID) {
        guard let peek = window.peek, peek.id == id else { return }
        let url = peek.page.url ?? peek.url
        guard let opener = session.tabs.first(where: { $0.id == peek.openerTabID }), let profileID = profileID(of: opener),
              let tab = addTab(url, in: opener.spaceID) else { return endPeek(id) }
        window.peek = nil
        resetPeekPresentation()
        pages.adoptPeekPage(peek.page, as: tab.id, profileID: profileID)
        updateTab(tab.id, url: url, title: peek.page.webView.title ?? "")
        selectTab(tab.id)
        extensionsDidOpenNavigationTarget(tab.id, from: opener.id)
    }

    private func resetPeekPresentation() {
        window.peekPressure = 0
        window.peekReveal = 0
        window.peekExpanded = false
    }

    /// Previews a link of the selected tab. Behind a prompt, the control bar or the onboarding, nothing opens.
    private func startPeek(_ url: URL, from tabID: UUID, origin: CGRect?, phase: Peek.Phase) {
        guard isReady, !isChangingStructure, onboarding == nil, window.selectedTabID == tabID, window.prompt == nil,
              window.controlBar == nil else { return }
        endPeek()
        guard let page = pages.makePeekPage(url, from: tabID) else { return }
        resetPeekPresentation()
        window.peek = Peek(url: url, page: page, openerTabID: tabID, origin: origin, phase: phase)
    }
}
