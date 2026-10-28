import AppKit
import BrowserCore
import SwiftUI

/// The menu bar, arranged like Safari's, every item with its symbol (`menuIcons`): see docs/SHORTCUTS.md › Menus. Actions only reachable from the keyboard,
/// such as numbered tabs, and those Settings already covers, such as profiles, stay out of it.
struct BrowserMenuCommands: Commands {
    let application: BrowserModel
    /// Quitting works from every window, so it does not wait for the browser window's focus.
    let quit: () -> Void
    @FocusedValue(\.browserModel) private var browser
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button(BrowserCommand.checkForUpdates.title, systemImage: BrowserCommand.checkForUpdates.symbol) { application.perform(.checkForUpdates) }
                .keyboardShortcut(application.shortcuts.shortcut(for: .checkForUpdates))
                .disabled(!application.isEnabled(.checkForUpdates))
                .menuIcons()
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…", systemImage: "gearshape") { openWindow(id: SettingsView.windowID) }.keyboardShortcut(",").menuIcons()
        }
        CommandGroup(replacing: .appTermination) {
            Button("Quit Aero", systemImage: "power", action: quit).keyboardShortcut("q").menuIcons()
        }
        CommandGroup(replacing: .newItem) {
            command(.newTab)
            command(.newTerminal)
            command(.openLocation)
            command(.openFile)
            command(.commandPalette)
        }
        // One window: Close All has nothing more to close.
        CommandGroup(replacing: .saveItem) {
            closeTab
            Button("Close Window", systemImage: "macwindow") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w", modifiers: [.command, .shift])
                .menuIcons()
            Divider()
            command(.savePage)
            command(.exportAsPDF)
            command(.capturePortrait)
            Divider()
            command(.importBrowserData)
        }
        CommandGroup(replacing: .printItem) { command(.printPage) }
        CommandGroup(after: .pasteboard) {
            command(.copyLink)
            Divider()
            Menu("Find", systemImage: "magnifyingglass") {
                command(.findInPage)
                command(.findNext)
                command(.findPrevious)
            }
            .menuIcons()
        }
        CommandGroup(after: .toolbar) {
            let pinned = browser?.window.sidebarPinned ?? true
            command(.toggleSidebar, title: pinned ? String(localized: "Hide Sidebar") : String(localized: "Show Sidebar"))
            Divider()
            command(.reload)
            command(.reloadFromOrigin)
            command(.stopLoading)
            Divider()
            command(.zoomIn)
            command(.zoomOut)
            command(.resetZoom)
            Divider()
            command(.showDownloads)
            command(.controlCenter)
            command(.siteSettings)
            Divider()
        }
        CommandMenu("History") {
            command(.back)
            command(.forward)
            Divider()
            command(.reopenTab)
            Divider()
            command(.showHistory)
        }
        CommandMenu("Tabs") {
            command(.nextTab)
            command(.previousTab)
            Divider()
            let isFavorite = browser?.selectedTab?.isFavorite == true
            command(.toggleFavorite, title: isFavorite ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites"),
                    symbol: isFavorite ? "star.slash" : nil)
            command(.duplicateTab)
            command(.renameTab)
            command(.openPeekInTab)
            Divider()
            Menu("Split View", systemImage: BrowserCommand.newPane.symbol) {
                command(.newPane)
                Divider()
                command(.nextPane)
                command(.previousPane)
                Divider()
                command(.separateSplit)
            }
            .menuIcons()
            Divider()
            command(.newGroup)
            if let browser, browser.selectedTab != nil {
                let tabs = browser.tabs(browser.commandTabs)
                MoveToGroupMenu(browser: browser, tabs: tabs).disabled(!browser.isEnabled(.moveToGroup)).menuIcons()
                MoveToSpaceMenu(browser: browser, tabs: tabs).disabled(!browser.isEnabled(.moveToSpace)).menuIcons()
            } else {
                Menu("Move to Group", systemImage: BrowserCommand.moveToGroup.symbol) {}.disabled(true).menuIcons()
                Menu("Move to Space", systemImage: BrowserCommand.moveToSpace.symbol) {}.disabled(true).menuIcons()
            }
            Divider()
            command(.closeOtherTabs)
            command(.closeFollowingTabs)
        }
        CommandMenu("Spaces") {
            command(.newSpace)
            Divider()
            spaces
            Divider()
            command(.nextSpace)
            command(.previousSpace)
        }
    }

    /// Every space, checked when shown, under its profile's name once there are several profiles.
    @ViewBuilder private var spaces: some View {
        let profiles = application.profiles.filter { profile in application.session.spaces.contains { $0.profileID == profile.id } }
        ForEach(profiles) { profile in
            let spaces = application.session.spaces.filter { $0.profileID == profile.id }
            if profiles.count > 1 {
                Section(profile.name) { spaceToggles(spaces) }
            } else { spaceToggles(spaces) }
        }
    }

    private func spaceToggles(_ spaces: [BrowserSpace]) -> some View {
        ForEach(spaces) { space in
            Toggle(isOn: Binding(get: { application.window.selectedSpaceID == space.id }, set: { _ in
                application.switchSpace(space.id)
                openWindow(id: BrowserWindowView.windowID)
            })) { Text(verbatim: space.name) }
                .disabled(!application.isEnabled(.nextSpace))
        }
    }

    /// ⌘W closes the tab, or, in a window without tabs such as Settings, the window: the menu item
    /// would otherwise take the shortcut from the system's Close even while disabled.
    private var closeTab: some View {
        Button(BrowserCommand.closeTab.title, systemImage: BrowserCommand.closeTab.symbol) {
            if let browser { browser.perform(.closeTab) } else { NSApp.keyWindow?.performClose(nil) }
        }
        .keyboardShortcut(browser?.shortcuts.shortcut(for: .closeTab) ?? (browser == nil ? KeyboardShortcut("w") : nil))
        .disabled(browser.map { !$0.isEnabled(.closeTab) } ?? false)
        .menuIcons()
    }

    private func command(_ command: BrowserCommand, title: String? = nil, symbol: String? = nil) -> some View {
        Button(title ?? command.title, systemImage: symbol ?? command.symbol) { browser?.perform(command) }
            .keyboardShortcut(browser?.shortcuts.shortcut(for: command))
            .disabled(browser?.isEnabled(command) != true)
            .menuIcons()
    }
}

extension FocusedValues {
    @Entry var browserModel: BrowserModel?
}
