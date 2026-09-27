import BrowserCore
import SwiftUI

/// Everything a tab or a favorite can do, from its context menu.
struct TabContextMenu: View {
    let browser: BrowserModel
    let tab: BrowserTab

    var body: some View {
        if tab.isFavorite {
            Button("Remove from Favorites", systemImage: "star.slash") { browser.removeFavorite(tab.id) }
        } else {
            Button("Add to Favorites", systemImage: "star") { browser.moveTab(tab.id, to: .grid, before: nil) }
        }
        if tab.place != .list(group: nil) {
            Button("Pin as Tab", systemImage: "pin") { browser.moveTab(tab.id, to: .list(group: nil), before: nil) }
        }
        if tab.isFavorite, tab.place != .grid {
            Button("Move to Favorites Grid", systemImage: "square.grid.3x3") { browser.moveTab(tab.id, to: .grid, before: nil) }
        }
        Button("Duplicate", systemImage: "plus.square.on.square") { browser.duplicateTab(tab.id) }
        Divider()
        Button("New Group with Tab", systemImage: "folder.badge.plus") { browser.newGroup(with: tab.id) }
        let groups = browser.session.spaces.first { $0.id == tab.spaceID }?.groups ?? []
        if !groups.isEmpty {
            Menu("Move to Group", systemImage: "folder") {
                ForEach(groups) { group in
                    Button { browser.moveTab(tab.id, to: .list(group: group.id), before: nil) } label: { Text(verbatim: group.name) }
                        .disabled(tab.place == .list(group: group.id))
                }
                if case .list(group: .some) = tab.place {
                    Divider()
                    Button("Out of Group") { browser.moveTab(tab.id, to: .list(group: nil), before: nil) }
                }
            }
        }
        let spaces = browser.session.spaces.filter { $0.id != tab.spaceID }
        if !spaces.isEmpty {
            Menu("Move to Space", systemImage: "square.stack") {
                ForEach(spaces) { space in
                    Button { browser.moveTab(tab.id, toSpace: space.id) } label: { Text(verbatim: space.name) }
                }
            }
        }
        Divider()
        Button("Rename…", systemImage: "pencil") { browser.window.renaming = .tab(tab.id) }
        Divider()
        Button("Close", systemImage: "xmark") { browser.closeTab(tab.id) }
    }
}
