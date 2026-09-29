import BrowserCore
import SwiftUI

/// Everything a tab or a favorite can do, from its context menu: the tab itself, where it is kept, how it is
/// organized, then closing it. See docs/SHORTCUTS.md › Context menus.
struct TabContextMenu: View {
    let browser: BrowserModel
    let tab: BrowserTab

    var body: some View {
        Button("Copy Link", systemImage: BrowserCommand.copyLink.symbol) { browser.copyLink(of: tab) }
        Divider()
        Button("Duplicate Tab", systemImage: BrowserCommand.duplicateTab.symbol) { browser.duplicateTab(tab.id) }
        Button("Rename Tab…", systemImage: BrowserCommand.renameTab.symbol) { browser.window.renaming = .tab(tab.id) }
        Divider()
        // Favorites show in the grid or, pinned, in the list under it with the groups.
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
        Button("New Group with Tab", systemImage: BrowserCommand.newGroup.symbol) { browser.newGroup(with: tab.id) }
        if !(browser.session.spaces.first { $0.id == tab.spaceID }?.groups.isEmpty ?? true) {
            MoveToGroupMenu(browser: browser, tab: tab)
        }
        if browser.session.spaces.count > 1 {
            MoveToSpaceMenu(browser: browser, tab: tab)
        }
        // A closed favorite has nothing to close.
        if browser.isTabOpen(tab) {
            Divider()
            Button("Close Tab", systemImage: BrowserCommand.closeTab.symbol) { browser.closeTab(tab.id) }
        }
    }
}
