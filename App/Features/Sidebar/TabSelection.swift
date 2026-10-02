import AppKit
import BrowserCore

/// The tabs and groups picked with ⌘ or ⇧ in the sidebar, besides the tab shown, for acting on several at once. It
/// belongs to the window and is never saved; showing another tab, changing space or Escape ends it.
/// See docs/BROWSING.md › Several tabs at once.
struct TabSelection: Equatable {
    /// In the order they were picked; actions put them in sidebar order.
    private(set) var ids: [UUID] = []
    /// Where a ⇧-click range starts: the last tab ⌘-clicked, else the shown one.
    private var anchor: UUID?

    var isEmpty: Bool { ids.isEmpty }

    func contains(_ id: UUID) -> Bool { ids.contains(id) }

    /// ⌘-click: picks or drops `id`. The first pick keeps the shown tab with it.
    mutating func toggle(_ id: UUID, shown: UUID?) {
        if ids.isEmpty, let shown, shown != id { ids = [shown] }
        if let index = ids.firstIndex(of: id) { ids.remove(at: index) } else { ids.append(id) }
        anchor = id
    }

    /// ⇧-click: every tab on screen from the anchor to `id`, in either direction.
    mutating func extend(to id: UUID, shown: UUID?, visible order: [UUID]) {
        guard let end = order.firstIndex(of: id) else { return }
        let start = [anchor, shown].lazy.compactMap { $0 }.compactMap { order.firstIndex(of: $0) }.first ?? end
        ids = Array(order[min(start, end)...max(start, end)])
        anchor = order[start]
    }

    mutating func clear() { self = TabSelection() }

    /// What an action on `id` applies to: every picked tab still there, in sidebar order, when `id` is one of them;
    /// otherwise `id` alone, as a right-click outside the selection means.
    func targets(for id: UUID, in order: [UUID]) -> [UUID] {
        guard ids.count > 1, ids.contains(id) else { return [id] }
        let targets = order.filter(ids.contains)
        return targets.count > 1 ? targets : [id]
    }
}

extension BrowserModel {
    /// A click on a tab in the sidebar: ⌘ picks it, ⇧ picks the range up to it, a plain click shows it.
    func click(_ tab: BrowserTab, modifiers: NSEvent.ModifierFlags) {
        guard tab.spaceID == window.selectedSpaceID, let space else { showTab(tab); return }
        if modifiers.contains(.command) {
            window.tabSelection.toggle(tab.id, shown: window.selectedTabID)
        } else if modifiers.contains(.shift) {
            let order = SidebarTabs(session: session, space: space, drop: nil).visibleOrder
            window.tabSelection.extend(to: tab.id, shown: window.selectedTabID, visible: order)
        } else {
            window.tabSelection.clear()
            showTab(tab)
        }
    }

    /// A click on a group's header: ⌘ picks it, ⇧ picks the range up to it, a plain click opens or closes it.
    func click(_ group: TabGroup, modifiers: NSEvent.ModifierFlags) {
        guard let space, space.groups.contains(where: { $0.id == group.id }) else { return }
        if modifiers.contains(.command) {
            window.tabSelection.toggle(group.id, shown: window.selectedTabID)
        } else if modifiers.contains(.shift) {
            let order = SidebarTabs(session: session, space: space, drop: nil).visibleOrder
            window.tabSelection.extend(to: group.id, shown: window.selectedTabID, visible: order)
        } else {
            window.tabSelection.clear()
            setGroupCollapsed(group.id, !group.isCollapsed)
        }
    }

    /// The groups and tabs an action on `id` applies to when the selection holds a group as well as `id`, in sidebar
    /// order; a tab in a picked group goes with it. Nil otherwise: tabs alone act through `selectedTabs(for:)`.
    func selectedEntries(for id: UUID) -> [PinnedItem]? {
        let selection = window.tabSelection
        guard let space, selection.ids.count > 1, selection.contains(id) else { return nil }
        return SidebarTabs(session: session, space: space, drop: nil).entries(of: Set(selection.ids))
    }

    /// Starts a drag from the sidebar: what was picked up and, when it is part of the selection, the rest of it.
    func beginDrag(_ picked: PinnedItem) {
        let shown = window.selectedTabID
        switch picked {
        case .tab(let id):
            guard let tab = session.tabs.first(where: { $0.id == id }) else { return }
            let items = selectedEntries(for: id) ?? selectedTabs(for: id).map(PinnedItem.tab)
            window.tabDrag = TabDrag(picked: picked, items: items, spaceID: tab.spaceID, shownTabID: shown)
        case .group(let id):
            guard let space = session.spaces.first(where: { $0.groups.contains { $0.id == id } }) else { return }
            window.tabDrag = TabDrag(picked: picked, items: selectedEntries(for: id) ?? [picked], spaceID: space.id, shownTabID: shown)
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }

    /// The tabs an action on `id` applies to (see `TabSelection.targets`).
    func selectedTabs(for id: UUID) -> [UUID] {
        window.tabSelection.targets(for: id, in: orderedTabs.map(\.id))
    }

    /// What the Tabs menu and its shortcuts act on: the selection when it includes the shown tab.
    var commandTabs: [UUID] { window.selectedTabID.map(selectedTabs(for:)) ?? [] }

    func tabs(_ ids: [UUID]) -> [BrowserTab] {
        ids.compactMap { id in session.tabs.first { $0.id == id } }
    }

    /// One tab is shown once copied, as Duplicate Tab does; several stay where they are.
    func duplicateTabs(_ ids: [UUID]) {
        if ids.count == 1 { duplicateTab(ids[0]); return }
        for id in ids { duplicateTab(id, select: false) }
        window.tabSelection.clear()
    }

    /// Keeps their order: each goes before the same tab, or to the same end.
    func moveTabs(_ ids: [UUID], to place: TabPlace, before targetID: UUID?) {
        for id in ids where id != targetID { moveTab(id, to: place, before: targetID) }
    }

    func closeTabs(_ ids: [UUID]) {
        for id in ids { closeTab(id) }
        window.tabSelection.clear()
    }

    func copyLinks(of ids: [UUID]) {
        copy(tabs(ids).map { $0.id == window.selectedTabID ? currentAddress ?? $0.url : $0.url })
    }

    /// The group asks for its name at once.
    func newGroup(with tabIDs: [UUID]) {
        guard !isChangingStructure, let first = tabIDs.first,
              let spaceID = session.tabs.first(where: { $0.id == first })?.spaceID,
              let group = session.addGroup(named: String(localized: "New Group"), in: spaceID) else { return }
        moveTabs(tabIDs, to: .list(group: group.id), before: nil)
        window.tabSelection.clear()
        window.renaming = .group(group.id)
    }
}
