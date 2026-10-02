import BrowserCore
import SwiftUI

/// Everything a tab or a favorite can do, from its context menu: the tab itself, where it is kept, how it is
/// organized, then closing it. On a tab picked with others, it acts on all of them. See docs/SHORTCUTS.md › Context menus.
struct TabContextMenu: View {
    let browser: BrowserModel
    let tab: BrowserTab

    var body: some View {
        let selected = browser.selectedTabs(for: tab.id)
        if let entries = browser.selectedEntries(for: tab.id) {
            SelectedEntriesMenu(browser: browser, entries: entries)
        } else if selected.count > 1 {
            SelectedTabsMenu(browser: browser, tabs: browser.tabs(selected))
        } else {
            singleTab
        }
    }

    @ViewBuilder private var singleTab: some View {
        Button("Copy Link", systemImage: BrowserCommand.copyLink.symbol) { browser.copyLink(of: tab) }
        Divider()
        Button("Duplicate Tab", systemImage: BrowserCommand.duplicateTab.symbol) { browser.duplicateTab(tab.id) }
        Button("Rename Tab…", systemImage: BrowserCommand.renameTab.symbol) { browser.window.renaming = .tab(tab.id) }
        Divider()
        // Favorites show in the grid or, pinned, in the list under it, among the groups.
        switch tab.place {
        case .open:
            Button("Add to Favorites", systemImage: "star") { browser.moveTab(tab.id, to: .grid, before: nil) }
            Button("Pin Tab", systemImage: "pin") { browser.moveTab(tab.id, to: .list(group: nil), before: nil) }
        case .grid:
            Button("Move to Pinned Tabs", systemImage: "pin") { browser.moveTab(tab.id, to: .list(group: nil), before: nil) }
            Button("Remove from Favorites", systemImage: "star.slash") { browser.removeFavorite(tab.id) }
        case .list:
            Button("Move to Favorites Grid", systemImage: "square.grid.2x2") { browser.moveTab(tab.id, to: .grid, before: nil) }
            Button("Remove from Favorites", systemImage: "star.slash") { browser.removeFavorite(tab.id) }
        }
        Divider()
        Button("New Group with Tab", systemImage: BrowserCommand.newGroup.symbol) { browser.newGroup(with: [tab.id]) }
        if !(browser.session.spaces.first { $0.id == tab.spaceID }?.groups.isEmpty ?? true) {
            MoveToGroupMenu(browser: browser, tabs: [tab])
        }
        if browser.session.spaces.count > 1 {
            MoveToSpaceMenu(browser: browser, tabs: [tab])
        }
        // A closed favorite has nothing to close.
        if browser.isTabOpen(tab) {
            Divider()
            Button("Close Tab", systemImage: BrowserCommand.closeTab.symbol) { browser.closeTab(tab.id) }
        }
    }
}

/// The context menu of a tab picked with others: what makes sense for all of them at once, counted.
private struct SelectedTabsMenu: View {
    let browser: BrowserModel
    let tabs: [BrowserTab]

    var body: some View {
        let ids = tabs.map(\.id)
        Button("Copy Links", systemImage: BrowserCommand.copyLink.symbol) { browser.copyLinks(of: ids) }
        Divider()
        Button("Duplicate \(tabs.count) Tabs", systemImage: BrowserCommand.duplicateTab.symbol) { browser.duplicateTabs(ids) }
        Divider()
        Button("Add to Favorites", systemImage: "star") { place(.grid) }
            .disabled(tabs.allSatisfy { $0.place == .grid })
        Button("Pin Tabs", systemImage: "pin") { place(.list(group: nil)) }
            .disabled(tabs.allSatisfy { $0.place == .list(group: nil) })
        Divider()
        Button("New Group with \(tabs.count) Tabs", systemImage: BrowserCommand.newGroup.symbol) { browser.newGroup(with: ids) }
        if !(browser.space?.groups.isEmpty ?? true) {
            MoveToGroupMenu(browser: browser, tabs: tabs)
        }
        if browser.session.spaces.count > 1 {
            MoveToSpaceMenu(browser: browser, tabs: tabs)
        }
        Divider()
        Button("Close \(tabs.count) Tabs", systemImage: BrowserCommand.closeTab.symbol) { browser.closeTabs(ids) }
    }

    private func place(_ place: TabPlace) {
        browser.moveTabs(tabs.filter { $0.place != place }.map(\.id), to: place, before: nil)
        browser.window.tabSelection.clear()
    }
}

/// The context menu of a group or tab picked along with groups: what applies to groups and tabs at once.
struct SelectedEntriesMenu: View {
    let browser: BrowserModel
    let entries: [PinnedItem]

    var body: some View {
        let groups = entries.compactMap { if case .group(let id) = $0 { id } else { nil } }
        let collapsed = browser.space?.groups.filter { groups.contains($0.id) && $0.isCollapsed } ?? []
        Button("Copy Links", systemImage: BrowserCommand.copyLink.symbol) { browser.copyLinks(of: browser.tabIDs(of: entries)) }
        Divider()
        Button(collapsed.isEmpty ? "Collapse Groups" : "Expand Groups", systemImage: collapsed.isEmpty ? "chevron.up" : "chevron.down") {
            for group in groups { browser.setGroupCollapsed(group, !collapsed.isEmpty) }
            browser.window.tabSelection.clear()
        }
        if browser.session.spaces.count > 1 {
            MoveToSpaceMenu(browser: browser, isCurrent: { $0.id == browser.space?.id }) { space in
                browser.moveEntries(entries, toSpace: space.id)
            }
        }
        Divider()
        // Their tabs stay pinned where each group was.
        Button("Ungroup", systemImage: "folder.badge.minus") {
            for group in groups { browser.removeGroup(group) }
            browser.window.tabSelection.clear()
        }
    }
}
