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
        case .profiles: nil
        case .showHistory: KeyboardShortcut("y")
        case .findInPage: KeyboardShortcut("f")
        case .findNext: KeyboardShortcut("g")
        case .findPrevious: KeyboardShortcut("g", modifiers: [.command, .shift])
        }
    }
}

extension KeyboardShortcut {
    /// Menu notation, with modifiers in the system order: “⇧ ⌘ T”.
    var label: String {
        let symbols: [(EventModifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        let key = key == .tab ? "⇥" : String(key.character).uppercased()
        return (symbols.filter { modifiers.contains($0.0) }.map(\.1) + [key]).joined(separator: " ")
    }
}

extension BrowserModel {
    func isEnabled(_ command: BrowserCommand) -> Bool {
        guard isReady else { return false }
        switch command {
        case .back: return currentPage?.canGoBack == true
        case .forward: return currentPage?.canGoForward == true
        case .reload: return currentPage != nil
        case .closeTab: return selectedTab != nil
        case .findInPage, .findNext, .findPrevious: return currentPage != nil
        case .reopenTab: return canReopen
        default: return true
        }
    }

    func perform(_ command: BrowserCommand) {
        guard isEnabled(command) else { return }
        switch command {
        case .newTab:
            window.commandBar = nil
            selectTab(nil)
            window.inputFocusRequest = UUID()
        case .openLocation:
            if let selectedTab { window.commandBar = CommandBarRequest(replacing: true, initialText: selectedTab.url.absoluteString) }
            else { window.inputFocusRequest = UUID() }
        case .commandPalette: window.commandBar = CommandBarRequest(replacing: false, initialText: "")
        case .back: currentPage?.goBack()
        case .forward: currentPage?.goForward()
        case .reload: currentPage?.reload()
        case .closeTab: if let id = window.selectedTabID { closeTab(id) }
        case .reopenTab: reopenTab()
        case .toggleSidebar: window.sidebarPinned.toggle()
        case .profiles: window.profilesPresented = true
        case .showHistory: show(.history)
        case .findInPage, .findNext, .findPrevious: find(command)
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
    @FocusedValue(\.browserModel) private var browser
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
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
