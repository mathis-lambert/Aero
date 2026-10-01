import BrowserCore
import SwiftUI

extension BrowserCommand {
    var title: String {
        switch self {
        case .checkForUpdates: String(localized: "Check for Updates…")
        case .zoomIn: String(localized: "Zoom In")
        case .zoomOut: String(localized: "Zoom Out")
        case .resetZoom: String(localized: "Actual Size")
        case .reloadFromOrigin: String(localized: "Reload Without Cache")
        case .stopLoading: String(localized: "Stop Loading")
        case .printPage: String(localized: "Print…")
        case .showDownloads: String(localized: "Show Downloads")
        case .nextTab: String(localized: "Next Tab")
        case .previousTab: String(localized: "Previous Tab")
        case .recentTab: String(localized: "Next Recently Used Tab")
        case .previousRecentTab: String(localized: "Previous Recently Used Tab")
        case .tab1: String(localized: "Select Tab 1")
        case .tab2: String(localized: "Select Tab 2")
        case .tab3: String(localized: "Select Tab 3")
        case .tab4: String(localized: "Select Tab 4")
        case .tab5: String(localized: "Select Tab 5")
        case .tab6: String(localized: "Select Tab 6")
        case .tab7: String(localized: "Select Tab 7")
        case .tab8: String(localized: "Select Tab 8")
        case .lastTab: String(localized: "Select Last Tab")
        case .toggleFavorite: String(localized: "Toggle Favorite")
        case .duplicateTab: String(localized: "Duplicate Tab")
        case .renameTab: String(localized: "Rename Tab…")
        case .closeOtherTabs: String(localized: "Close Other Tabs")
        case .closeFollowingTabs: String(localized: "Close Tabs Below")
        case .newGroup: String(localized: "New Group with Tab")
        case .moveToGroup: String(localized: "Move to Group…")
        case .moveToSpace: String(localized: "Move to Space…")
        case .nextSpace: String(localized: "Next Space")
        case .previousSpace: String(localized: "Previous Space")
        case .newTab: String(localized: "New Tab")
        case .openLocation: String(localized: "Open Location…")
        case .commandPalette: String(localized: "Command Bar")
        case .back: String(localized: "Back")
        case .forward: String(localized: "Forward")
        case .reload: String(localized: "Reload Page")
        case .closeTab: String(localized: "Close Tab")
        case .reopenTab: String(localized: "Reopen Closed Tab")
        case .toggleSidebar: String(localized: "Toggle Sidebar")
        case .newProfile: String(localized: "New Profile…")
        case .newSpace: String(localized: "New Space…")
        case .profiles: String(localized: "Manage Profiles")
        case .passwords: String(localized: "Passwords")
        case .importBrowserData: String(localized: "Import from Another Browser…")
        case .openFile: String(localized: "Open File…")
        case .savePage: String(localized: "Save As…")
        case .exportAsPDF: String(localized: "Export as PDF…")
        case .showHistory: String(localized: "Show All History")
        case .findInPage: String(localized: "Find…")
        case .findNext: String(localized: "Find Next")
        case .findPrevious: String(localized: "Find Previous")
        case .copyLink: String(localized: "Copy Link")
        case .controlCenter: String(localized: "Site Controls")
        case .clearCookies: String(localized: "Clear Cookies")
        case .clearCache: String(localized: "Clear Cache")
        case .siteSettings: String(localized: "Site Settings…")
        }
    }

    var summary: String {
        switch self {
        case .checkForUpdates: String(localized: "Check for a newer version of Aero.")
        case .newTab: String(localized: "Open a new tab in the current space.")
        case .openLocation: String(localized: "Focus the current address to enter a URL or search.")
        case .commandPalette: String(localized: "Search tabs, history, and browser commands.")
        case .back: String(localized: "Return to the previous page in this tab.")
        case .forward: String(localized: "Go to the next page in this tab’s history.")
        case .reload: String(localized: "Reload the current page.")
        case .reloadFromOrigin: String(localized: "Reload the page from its server without using cached content.")
        case .stopLoading: String(localized: "Stop the current page’s loading request.")
        case .closeTab: String(localized: "Close the current tab. Favorites remain available in the sidebar.")
        case .reopenTab: String(localized: "Restore the most recently closed tab.")
        case .toggleSidebar: String(localized: "Show or hide the browser sidebar.")
        case .newProfile: String(localized: "Create a separate browsing identity.")
        case .newSpace: String(localized: "Create a space for your tabs.")
        case .profiles: String(localized: "Manage browsing identities and their spaces.")
        case .passwords: String(localized: "Show the passwords saved in this profile.")
        case .openFile: String(localized: "Open a web page, image or PDF from this Mac in a new tab.")
        case .savePage: String(localized: "Save the page as a web archive, with its images and styles.")
        case .exportAsPDF: String(localized: "Save the whole page as a PDF document.")
        case .importBrowserData: String(localized: "Bring favorites, history and passwords from another browser.")
        case .showHistory: String(localized: "Open browsing history for the current profile.")
        case .findInPage: String(localized: "Find text on the current page.")
        case .findNext: String(localized: "Select the next matching text on the page.")
        case .findPrevious: String(localized: "Select the previous matching text on the page.")
        case .copyLink: String(localized: "Copy the current page’s address to the clipboard.")
        case .controlCenter: String(localized: "Open the current site’s controls and extensions.")
        case .clearCookies: String(localized: "Remove the current site’s cookies. This may sign you out.")
        case .clearCache: String(localized: "Remove cached content for the current site.")
        case .siteSettings: String(localized: "Change permissions and preferences for the current site.")
        case .zoomIn: String(localized: "Make the current page larger.")
        case .zoomOut: String(localized: "Make the current page smaller.")
        case .resetZoom: String(localized: "Restore the current page to 100% zoom.")
        case .printPage: String(localized: "Open the native print dialog for the current page.")
        case .showDownloads: String(localized: "Show downloads from this browsing session.")
        case .nextTab, .previousTab: String(localized: "Switch tabs in sidebar order, including favorites and collapsed groups.")
        case .recentTab, .previousRecentTab: String(localized: "Switch between recently used tabs. Release the modifiers to choose.")
        case .tab1, .tab2, .tab3, .tab4, .tab5, .tab6, .tab7, .tab8: String(localized: "Select this position in sidebar order, with favorites first.")
        case .lastTab: String(localized: "Select the last tab in sidebar order.")
        case .toggleFavorite: String(localized: "Add the current tab to favorites or return it to open tabs.")
        case .duplicateTab: String(localized: "Open a copy of the current tab in this space.")
        case .renameTab: String(localized: "Give the current tab a custom name.")
        case .closeOtherTabs: String(localized: "Close the other tabs in this space. Favorite records are kept.")
        case .closeFollowingTabs: String(localized: "Close the tabs below the current tab in sidebar order. Favorite records are kept.")
        case .newGroup: String(localized: "Create a group containing the current tab and choose its name.")
        case .moveToGroup: String(localized: "Choose a group for the current tab.")
        case .moveToSpace: String(localized: "Move the current tab to another space.")
        case .nextSpace, .previousSpace: String(localized: "Switch spaces in their listed order.")
        }
    }

    var symbol: String {
        switch self {
        case .checkForUpdates: "arrow.triangle.2.circlepath"
        case .zoomIn: "plus.magnifyingglass"
        case .zoomOut: "minus.magnifyingglass"
        case .resetZoom: "1.magnifyingglass"
        case .reloadFromOrigin: "arrow.clockwise.circle"
        case .stopLoading: "xmark"
        case .printPage: "printer"
        case .showDownloads: "arrow.down.circle"
        case .nextTab: "arrow.down"
        case .previousTab: "arrow.up"
        case .recentTab: "arrow.turn.down.right"
        case .previousRecentTab: "arrow.turn.down.left"
        case .tab1: "square"
        case .tab2: "square"
        case .tab3: "square"
        case .tab4: "square"
        case .tab5: "square"
        case .tab6: "square"
        case .tab7: "square"
        case .tab8: "square"
        case .lastTab: "square"
        case .toggleFavorite: "star"
        case .duplicateTab: "plus.square.on.square"
        case .renameTab: "pencil"
        case .closeOtherTabs: "xmark.square"
        case .closeFollowingTabs: "arrow.down.to.line"
        case .newGroup: "folder.badge.plus"
        case .moveToGroup: "folder"
        case .moveToSpace: "rectangle.stack"
        case .nextSpace: "arrow.right.square"
        case .previousSpace: "arrow.left.square"
        case .newTab: "plus"
        case .openLocation: "magnifyingglass"
        case .commandPalette: "command"
        case .back: "chevron.backward"
        case .forward: "chevron.forward"
        case .reload: "arrow.clockwise"
        case .closeTab: "xmark"
        case .reopenTab: "arrow.uturn.backward"
        case .toggleSidebar: "sidebar.left"
        case .newProfile: "person.badge.plus"
        case .newSpace: "plus.square"
        case .profiles: "person.crop.circle"
        case .passwords: "key"
        case .importBrowserData: "square.and.arrow.down"
        case .openFile: "doc"
        case .savePage: "square.and.arrow.down.on.square"
        case .exportAsPDF: "doc.richtext"
        case .showHistory: "clock"
        case .findInPage: "text.magnifyingglass"
        case .findNext: "chevron.down"
        case .findPrevious: "chevron.up"
        case .copyLink: "link"
        case .controlCenter: "switch.2"
        case .clearCookies: "trash"
        case .clearCache: "externaldrive.badge.xmark"
        case .siteSettings: "slider.horizontal.3"
        }
    }
}

extension BrowserCommand {
    enum Category: String, CaseIterable, Identifiable {
        case navigation, tabs, page, spaces, profiles
        var id: Self { self }
        var title: String {
            switch self {
            case .navigation: String(localized: "Navigation")
            case .tabs: String(localized: "Tabs")
            case .page: String(localized: "Page")
            case .spaces: String(localized: "Spaces")
            case .profiles: String(localized: "Profiles")
            }
        }
    }

    var category: Category {
        switch self {
        case .newTab, .closeTab, .reopenTab, .nextTab, .previousTab, .recentTab, .previousRecentTab,
             .tab1, .tab2, .tab3, .tab4, .tab5, .tab6, .tab7, .tab8, .lastTab,
             .toggleFavorite, .duplicateTab, .renameTab, .closeOtherTabs, .closeFollowingTabs, .newGroup, .moveToGroup, .moveToSpace: .tabs
        case .profiles, .newProfile, .passwords, .importBrowserData: .profiles
        case .newSpace, .nextSpace, .previousSpace: .spaces
        case .reload, .reloadFromOrigin, .stopLoading, .zoomIn, .zoomOut, .resetZoom, .printPage,
             .findInPage, .findNext, .findPrevious, .copyLink, .controlCenter, .clearCookies, .clearCache, .siteSettings, .savePage, .exportAsPDF: .page
        default: .navigation
        }
    }

    func matchesSearch(_ query: String) -> Bool {
        if title.localizedStandardContains(query) { return true }
        // Keep the familiar menu title while making the reset action discoverable with the other zoom actions.
        return self == .resetZoom && String(localized: "zoom reset 100%").localizedStandardContains(query)
    }

    var tabIndex: Int? {
        [.tab1, .tab2, .tab3, .tab4, .tab5, .tab6, .tab7, .tab8].firstIndex(of: self)
    }

    var defaultBindings: [ShortcutBinding] {
        if let tabIndex { return [.init(String(tabIndex + 1))] }
        switch self {
        case .newTab: return [.init("t")]
        case .openLocation: return [.init("l")]
        case .commandPalette: return [.init("k")]
        case .back: return [.init("[")]
        case .forward: return [.init("]")]
        case .reload: return [.init("r")]
        case .closeTab: return [.init("w")]
        case .reopenTab: return [.init("t", [.command, .shift])]
        case .toggleSidebar: return [.init("s")]
        case .copyLink: return [.init("c", [.command, .shift])]
        case .showHistory: return [.init("y")]
        case .findInPage: return [.init("f")]
        case .findNext: return [.init("g")]
        case .findPrevious: return [.init("g", [.command, .shift])]
        case .zoomIn: return [.init("+")]
        case .zoomOut: return [.init("-")]
        case .resetZoom: return [.init("0")]
        case .reloadFromOrigin: return [.init("r", [.command, .shift])]
        case .stopLoading: return [.init(".")]
        case .printPage: return [.init("p")]
        case .openFile: return [.init("o")]
        case .savePage: return [.init("s", [.command, .shift])]
        case .showDownloads: return [.init("j", [.command, .shift])]
        case .nextTab: return [.init(String(KeyEquivalent.rightArrow.character), [.command, .option])]
        case .previousTab: return [.init(String(KeyEquivalent.leftArrow.character), [.command, .option])]
        case .nextSpace: return [.init(String(KeyEquivalent.rightArrow.character), [.command, .control])]
        case .previousSpace: return [.init(String(KeyEquivalent.leftArrow.character), [.command, .control])]
        case .recentTab: return [.init("\t", .control)]
        case .previousRecentTab: return [.init("\t", [.control, .shift])]
        case .lastTab: return [.init("9")]
        case .toggleFavorite: return [.init("d")]
        default: return []
        }
    }
}
