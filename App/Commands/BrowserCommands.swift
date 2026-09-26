import BrowserCore
import SwiftUI

extension BrowserCommand {
    var title: String {
        switch self {
        case .newTab: String(localized: "New tab")
        case .openLocation: String(localized: "Open location")
        case .commandPalette: String(localized: "Commands")
        case .back: String(localized: "Back")
        case .forward: String(localized: "Forward")
        case .reload: String(localized: "Reload page")
        case .closeTab: String(localized: "Close tab")
        case .reopenTab: String(localized: "Reopen closed tab")
        case .toggleSidebar: String(localized: "Toggle sidebar")
        case .profiles: String(localized: "Manage profiles")
        case .showHistory: String(localized: "Show all history")
        case .findInPage: String(localized: "Find…")
        case .findNext: String(localized: "Find next")
        case .findPrevious: String(localized: "Find previous")
        case .clearCookies: String(localized: "Clear cookies")
        case .clearCache: String(localized: "Clear cache")
        case .siteSettings: String(localized: "Site settings…")
        }
    }

    var symbol: String {
        switch self {
        case .newTab: "plus"
        case .openLocation: "magnifyingglass"
        case .commandPalette: "command"
        case .back: "arrow.left"
        case .forward: "arrow.right"
        case .reload: "arrow.clockwise"
        case .closeTab: "xmark"
        case .reopenTab: "arrow.uturn.backward"
        case .toggleSidebar: "sidebar.left"
        case .profiles: "person.crop.circle"
        case .showHistory: "clock"
        case .findInPage: "text.magnifyingglass"
        case .findNext: "chevron.down"
        case .findPrevious: "chevron.up"
        case .clearCookies: "trash"
        case .clearCache: "externaldrive.badge.xmark"
        case .siteSettings: "slider.horizontal.3"
        }
    }

    var shortcut: KeyboardShortcut? {
        switch self {
        case .newTab: KeyboardShortcut("t")
        case .openLocation: KeyboardShortcut("l")
        case .commandPalette: KeyboardShortcut("k")
        case .back: KeyboardShortcut("[")
        case .forward: KeyboardShortcut("]")
        case .reload: KeyboardShortcut("r")
        case .closeTab: KeyboardShortcut("w")
        case .reopenTab: KeyboardShortcut("t", modifiers: [.command, .shift])
        case .toggleSidebar: KeyboardShortcut("s", modifiers: [.command, .shift])
        case .profiles, .clearCookies, .clearCache, .siteSettings: nil
        case .showHistory: KeyboardShortcut("y")
        case .findInPage: KeyboardShortcut("f")
        case .findNext: KeyboardShortcut("g")
        case .findPrevious: KeyboardShortcut("g", modifiers: [.command, .shift])
        }
    }
}

extension BrowserModel {
    /// Nothing runs behind the quit prompt.
    func isEnabled(_ command: BrowserCommand) -> Bool {
        guard isReady, !window.quitPromptPresented else { return false }
        switch command {
        case .back: return currentPage?.canGoBack == true
        case .forward: return currentPage?.canGoForward == true
        case .reload: return currentPage != nil
        case .closeTab: return selectedTab != nil
        case .findInPage, .findNext, .findPrevious: return currentPage != nil
        case .reopenTab: return canReopen
        case .clearCookies, .clearCache, .siteSettings: return currentSite != nil
        default: return true
        }
    }

    func perform(_ command: BrowserCommand) {
        guard isEnabled(command) else { return }
        switch command {
        case .newTab:
            window.controlBar = nil
            selectTab(nil)
            window.inputFocusRequest = UUID()
        // The New Tab page's own bar takes both shortcuts, so a second bar never opens over it.
        case .openLocation:
            if let selectedTab { window.controlBar = ControlBarPresentation(target: .currentTab, initialText: selectedTab.url.absoluteString) }
            else { window.inputFocusRequest = UUID() }
        case .commandPalette:
            if selectedTab != nil { window.controlBar = ControlBarPresentation(target: .newTab, initialText: "") }
            else { window.inputFocusRequest = UUID() }
        case .back: currentPage?.goBack()
        case .forward: currentPage?.goForward()
        case .reload: currentPage?.reload()
        case .closeTab: if let id = window.selectedTabID { closeTab(id) }
        case .reopenTab: reopenTab()
        case .toggleSidebar: window.sidebarPinned.toggle()
        case .profiles: window.profileSheet = window.selectedProfileID.map(ProfileSheet.edit)
        case .showHistory: show(.history)
        case .findInPage, .findNext, .findPrevious: find(command)
        case .clearCookies: Task { await clearSiteData(.cookies) }
        case .clearCache: Task { await clearSiteData(.cache) }
        case .siteSettings: window.siteSettingsPresented = true
        }
    }

    /// Next and previous open the bar first when there is nothing to search for yet.
    private func find(_ command: BrowserCommand) {
        guard let page = currentPage else { return }
        let find = window.find
        Task {
            if command == .findInPage || find.query.isEmpty { await find.present(on: page) }
            else { await find.search(on: page, backwards: command == .findPrevious) }
        }
    }
}

struct BrowserMenuCommands: Commands {
    /// Quitting works from every window, so it does not wait for the browser window's focus.
    let quit: () -> Void
    @FocusedValue(\.browserModel) private var browser
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appTermination) {
            Button("Quit Aero", action: quit).keyboardShortcut("q")
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { openWindow(id: SettingsView.windowID) }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(replacing: .newItem) {
            command(.newTab)
            command(.openLocation)
            Divider()
            command(.closeTab)
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
        CommandMenu("History") {
            command(.showHistory)
        }
        CommandMenu("Navigate") {
            command(.back)
            command(.forward)
            command(.reload)
            Divider()
            command(.commandPalette)
            command(.toggleSidebar)
            Divider()
            command(.profiles)
        }
    }

    private func command(_ command: BrowserCommand) -> some View {
        Button(command.title) { browser?.perform(command) }
            .keyboardShortcut(command.shortcut)
            .disabled(browser?.isEnabled(command) != true)
    }
}

private struct BrowserModelFocusKey: FocusedValueKey {
    typealias Value = BrowserModel
}

extension FocusedValues {
    var browserModel: BrowserModel? {
        get { self[BrowserModelFocusKey.self] }
        set { self[BrowserModelFocusKey.self] = newValue }
    }
}
