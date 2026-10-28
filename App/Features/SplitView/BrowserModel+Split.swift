import BrowserCore
import Foundation

/// A New Tab page asked for in a pane beside a tab (docs/SPLIT_VIEW.md): window state, until it opens something or is
/// dismissed. Its identifier stands for it in the layout.
struct NewPane: Equatable {
    let id = UUID()
    /// The tab whose page it joins, at the trailing end.
    let tabID: UUID
}

/// Split views and terminal tabs (docs/SPLIT_VIEW.md, docs/TERMINAL.md). The session owns splits; selecting a pane
/// shows its split, and the selected tab is the focused pane.
extension BrowserModel {
    /// The split the selected tab is a pane of.
    var currentSplit: TabSplit? { window.selectedTabID.flatMap(session.split(containing:)) }

    /// Puts `tabID` beside `targetID`, at `edge` or where the space is widest, and focuses it. The tab joins the split
    /// where it is kept, among the open tabs or the favorites.
    func splitTab(_ tabID: UUID, beside targetID: UUID, at edge: SplitEdge? = nil) {
        guard !isChangingStructure else { return }
        let edge = edge ?? widestEdge(beside: targetID)
        guard movingTabs([tabID, targetID], { session.split(tabID, beside: targetID, at: edge) }) else { return }
        persist()
        selectTab(tabID)
    }

    /// Every pane closes; a favorite split stays, its panes unloaded. Shown, it hands over to a tab outside it first, so
    /// no pane is shown, and loaded again, as another closes.
    func closeSplit(_ ids: [UUID]) {
        if let shown = window.selectedTabID.flatMap(tab), ids.contains(shown.id) {
            selectTab(tabShown(afterRemoving: shown, along: Set(ids)))
        }
        for id in ids { closeTab(id, unloadingPanes: true) }
        window.tabSelection.clear()
    }

    /// A favorite split goes to the open tabs while any pane is loaded, as a favorite does; otherwise its panes go.
    func removeFavorite(split panes: [BrowserTab]) {
        guard let lead = panes.first, lead.isFavorite else { return }
        if panes.contains(where: isTabOpen) { moveTab(lead.id, to: .open, before: nil) }
        else { for pane in panes { removeFavorite(pane.id) } }
    }

    /// Where a new pane beside `targetID` halves the larger side of it, in a window of usual proportions.
    func widestEdge(beside targetID: UUID) -> SplitEdge {
        let root = session.split(containing: targetID)?.root ?? .pane(targetID)
        let frame = root.frames(in: CGRect(x: 0, y: 0, width: 1600, height: 1000), gap: 0)[targetID] ?? .zero
        return frame.width >= frame.height ? .trailing : .bottom
    }

    /// Two to four tabs side by side, in their order: each takes half of the largest pane so far.
    func openInSplit(_ ids: [UUID]) {
        guard !isChangingStructure, (2...TabSplit.maximumPanes).contains(ids.count), let first = ids.first else { return }
        for pane in ids.dropFirst() {
            let root = session.split(containing: first)?.root ?? .pane(first)
            let frames = root.frames(in: CGRect(x: 0, y: 0, width: 1600, height: 1000), gap: 0)
            let largest = frames.max { $0.value.width * $0.value.height < $1.value.width * $1.value.height }?.key ?? first
            let edge = widestEdge(beside: largest)
            _ = movingTabs([pane, largest]) { session.split(pane, beside: largest, at: edge) }
        }
        window.tabSelection.clear()
        persist()
        selectTab(first)
    }

    /// The pane leaves its split and stays an open tab, still focused.
    func removeFromSplit(_ tabID: UUID) {
        guard !isChangingStructure, session.split(containing: tabID) != nil else { return }
        session.removeFromSplit(tabID)
        persist()
        selectTab(tabID)
    }

    func separateSplit(_ splitID: UUID) {
        guard !isChangingStructure else { return }
        session.separate(splitID: splitID)
        persist()
        selectTab(window.selectedTabID)
    }

    func resizeSplit(_ splitID: UUID, divider: SplitDivider.Place, to boundary: Double) {
        session.resizeSplit(id: splitID, divider: divider, to: boundary)
        persist()
    }

    func equalizeSplit(_ splitID: UUID) {
        session.equalizeSplit(id: splitID)
        persist()
    }

    /// Focuses the next pane of the split, in reading order, or the previous one.
    func focusAdjacentPane(backwards: Bool) {
        guard let panes = currentSplit?.tabIDs, let id = window.selectedTabID, let index = panes.firstIndex(of: id) else { return }
        selectTab(panes[(index + (backwards ? panes.count - 1 : 1)) % panes.count])
    }

    /// Whether another pane fits beside the selected tab.
    var canAddPane: Bool { selectedTab != nil && (currentSplit?.tabIDs.count ?? 1) < TabSplit.maximumPanes }

    /// Shows a New Tab page in a pane at the trailing end of the page, whichever pane is focused; what it opens takes
    /// the pane's place.
    func beginNewPane() {
        guard canAddPane, let focused = window.selectedTabID else { return }
        window.newPane = NewPane(tabID: focused)
    }

    /// The New Tab pane opens `tabID` in its place, at the trailing end of the page; without one, `tabID` shows.
    func openInNewPane(_ tabID: UUID) {
        guard let pending = window.newPane else { selectTab(tabID); return }
        window.newPane = nil
        // Its page gone or full meanwhile, the tab shows on its own.
        if !isChangingStructure, movingTabs([tabID, pending.tabID], { session.split(tabID, alongside: pending.tabID, at: .trailing) }) {
            persist()
        }
        selectTab(tabID)
    }

    func cancelNewPane() {
        window.newPane = nil
    }

    /// The page's panes as they show: the split's, or the selected tab's alone, with a New Tab pane when one is asked;
    /// `nil` on the New Tab page.
    var paneLayout: SplitNode? {
        guard let base = currentSplit?.root ?? window.selectedTabID.map(SplitNode.pane) else { return nil }
        guard let pending = window.newPane else { return base }
        return base.inserting(pending.id, at: .trailing)
    }

    // MARK: Terminal

    /// A terminal on the right of the selected tab, in the folder of the selected terminal or the home folder; as a tab
    /// of its own on the New Tab page, or when the split is full.
    func openTerminal() {
        guard let spaceID = space?.id else { return }
        let directory = selectedTab.flatMap { InternalPage(url: $0.url) == .terminal ? terminals.existing($0.id)?.currentDirectory : nil }
            ?? FileManager.default.homeDirectoryForCurrentUser
        let focused = canAddPane ? window.selectedTabID : nil
        guard let tab = addTab(InternalPage.terminal(in: directory), in: spaceID) else { return }
        if let focused { splitTab(tab.id, beside: focused, at: .trailing) } else { selectTab(tab.id) }
    }

    /// The terminal tab's shell, started the first time it shows.
    func terminalSession(for tab: BrowserTab) -> TerminalSession {
        terminals.session(for: tab.id, in: InternalPage.terminalDirectory(of: tab.url)) { [weak self] title in
            guard let self, let current = session.tabs.first(where: { $0.id == tab.id }) else { return }
            updateTab(tab.id, url: current.url, title: title)
        }
    }

    /// Keeps the folder a terminal tab's shell is in, for its next shell after a relaunch.
    func recordTerminalDirectory(of tabID: UUID) {
        guard let terminal = terminals.existing(tabID), let tab = session.tabs.first(where: { $0.id == tabID }),
              InternalPage(url: tab.url) == .terminal else { return }
        let url = InternalPage.terminal(in: terminal.currentDirectory)
        if url != tab.url { updateTab(tabID, url: url, title: tab.title) }
    }
}
