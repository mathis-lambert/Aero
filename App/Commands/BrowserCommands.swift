import AppKit
import BrowserCore
import SwiftUI

struct BrowserMenuCommands: Commands {
    /// Quitting works from every window, so it does not wait for the browser window's focus.
    let quit: () -> Void
    @FocusedValue(\.browserModel) private var browser
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { openWindow(id: SettingsView.windowID) }
                .keyboardShortcut(",")
        }
        CommandGroup(replacing: .appTermination) {
            Button("Quit Aero", action: quit).keyboardShortcut("q")
        }
        CommandGroup(replacing: .newItem) {
            command(.newTab)
            command(.openLocation)
            Divider()
            closeTab
            command(.reopenTab)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Menu("Find") {
                command(.findInPage)
                command(.findNext)
                command(.findPrevious)
            }
        }
        CommandGroup(after: .toolbar) {
            command(.zoomIn)
            command(.zoomOut)
            command(.resetZoom)
            command(.showDownloads)
            command(.controlCenter)
            command(.siteSettings)
            command(.clearCookies)
            command(.clearCache)
            command(.copyLink)
        }
        CommandGroup(replacing: .printItem) { command(.printPage) }
        CommandMenu("Tabs") {
            ForEach(BrowserCommand.allCases.filter { $0.category == .tabs }, id: \.self) { item in
                if ![BrowserCommand.newTab, .closeTab, .reopenTab].contains(item) { command(item) }
            }
        }
        CommandMenu("History") {
            command(.showHistory)
        }
        CommandMenu("Navigate") {
            command(.back)
            command(.forward)
            command(.reload)
            command(.reloadFromOrigin)
            command(.stopLoading)
            Divider()
            command(.commandPalette)
            command(.toggleSidebar)
            Divider()
            command(.profiles)
            command(.nextProfile)
            command(.previousProfile)
        }
    }

    /// ⌘W closes the tab, or, in a window without tabs such as Settings, the window: the menu item
    /// would otherwise take the shortcut from the system's Close even while disabled.
    private var closeTab: some View {
        Button(BrowserCommand.closeTab.title) {
            if let browser { browser.perform(.closeTab) } else { NSApp.keyWindow?.performClose(nil) }
        }
        .keyboardShortcut(browser?.shortcuts.shortcut(for: .closeTab) ?? (browser == nil ? KeyboardShortcut("w") : nil))
        .disabled(browser.map { !$0.isEnabled(.closeTab) } ?? false)
    }

    private func command(_ command: BrowserCommand) -> some View {
        Button(command.title) { browser?.perform(command) }
            .keyboardShortcut(browser?.shortcuts.shortcut(for: command))
            .disabled(browser?.isEnabled(command) != true)
    }
}

extension FocusedValues {
    @Entry var browserModel: BrowserModel?
}
