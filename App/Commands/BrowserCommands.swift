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
        }
    }

    private var keyBinding: (shortcut: KeyboardShortcut, label: String)? {
        switch self {
        case .newTab: (KeyboardShortcut("t"), "⌘ T")
        case .openLocation: (KeyboardShortcut("l"), "⌘ L")
        case .commandPalette: (KeyboardShortcut("k"), "⌘ K")
        case .back: (KeyboardShortcut("["), "⌘ [")
        case .forward: (KeyboardShortcut("]"), "⌘ ]")
        case .reload: (KeyboardShortcut("r"), "⌘ R")
        case .closeTab: (KeyboardShortcut("w"), "⌘ W")
        case .reopenTab: (KeyboardShortcut("t", modifiers: [.command, .shift]), "⇧ ⌘ T")
        case .toggleSidebar: (KeyboardShortcut("s", modifiers: [.command, .shift]), "⇧ ⌘ S")
        case .profiles: nil
        }
    }

    var shortcut: KeyboardShortcut? { keyBinding?.shortcut }
    var shortcutLabel: String? { keyBinding?.label }
}

extension BrowserModel {
    func isEnabled(_ command: BrowserCommand) -> Bool {
        guard isReady else { return false }
        switch command {
        case .back: return currentPage?.canGoBack == true
        case .forward: return currentPage?.canGoForward == true
        case .reload, .closeTab: return selectedTab != nil
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
            window.newTabFocusID = UUID()
        case .openLocation:
            if let selectedTab { window.commandBar = CommandBarRequest(replacing: true, initialText: selectedTab.url.absoluteString) }
            else { window.newTabFocusID = UUID() }
        case .commandPalette: window.commandBar = CommandBarRequest(replacing: false, initialText: "")
        case .back: currentPage?.goBack()
        case .forward: currentPage?.goForward()
        case .reload: currentPage?.reload()
        case .closeTab: if let id = window.selectedTabID { closeTab(id) }
        case .reopenTab: reopenTab()
        case .toggleSidebar: window.sidebarPinned.toggle()
        case .profiles: window.profilesPresented = true
        }
    }
}

struct BrowserMenuCommands: Commands {
    @FocusedValue(\.browserModel) private var browser

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            command(.newTab)
            command(.openLocation)
            Divider()
            command(.closeTab)
            command(.reopenTab)
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
