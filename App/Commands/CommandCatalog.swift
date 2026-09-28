import BrowserCore
import SwiftUI

extension BrowserCommand {
    var title: String {
        switch self {
        case .zoomIn: String(localized: "Zoom in")
        case .zoomOut: String(localized: "Zoom out")
        case .resetZoom: String(localized: "Actual size")
        case .reloadFromOrigin: String(localized: "Reload without cache")
        case .stopLoading: String(localized: "Stop loading")
        case .printPage: String(localized: "Print…")
        case .showDownloads: String(localized: "Downloads")
        case .nextTab: String(localized: "Next tab")
        case .previousTab: String(localized: "Previous tab")
        case .recentTab: String(localized: "Next recently used tab")
        case .previousRecentTab: String(localized: "Previous recently used tab")
        case .tab1: String(localized: "Select tab 1")
        case .tab2: String(localized: "Select tab 2")
        case .tab3: String(localized: "Select tab 3")
        case .tab4: String(localized: "Select tab 4")
        case .tab5: String(localized: "Select tab 5")
        case .tab6: String(localized: "Select tab 6")
        case .tab7: String(localized: "Select tab 7")
        case .tab8: String(localized: "Select tab 8")
        case .lastTab: String(localized: "Select last tab")
        case .toggleFavorite: String(localized: "Toggle favorite")
        case .duplicateTab: String(localized: "Duplicate tab")
        case .renameTab: String(localized: "Rename tab…")
        case .closeOtherTabs: String(localized: "Close other tabs")
        case .closeFollowingTabs: String(localized: "Close following tabs")
        case .newGroup: String(localized: "New group with tab")
        case .moveToGroup: String(localized: "Move tab to group…")
        case .moveToSpace: String(localized: "Move tab to space…")
        case .nextSpace: String(localized: "Next space")
        case .previousSpace: String(localized: "Previous space")
        case .newTab: String(localized: "New tab")
        case .openLocation: String(localized: "Open location")
        case .commandPalette: String(localized: "Commands")
        case .back: String(localized: "Back")
        case .forward: String(localized: "Forward")
        case .reload: String(localized: "Reload page")
        case .closeTab: String(localized: "Close tab")
        case .reopenTab: String(localized: "Reopen closed tab")
        case .toggleSidebar: String(localized: "Toggle sidebar")
        case .newProfile: String(localized: "New profile")
        case .newSpace: String(localized: "New space")
        case .profiles: String(localized: "Manage profiles")
        case .passwords: String(localized: "Passwords")
        case .showHistory: String(localized: "Show all history")
        case .findInPage: String(localized: "Find…")
        case .findNext: String(localized: "Find next")
        case .findPrevious: String(localized: "Find previous")
        case .copyLink: String(localized: "Copy link")
        case .controlCenter: String(localized: "Site controls")
        case .clearCookies: String(localized: "Clear cookies")
        case .clearCache: String(localized: "Clear cache")
        case .siteSettings: String(localized: "Site settings…")
        }
    }

    var summary: String {
        switch self {
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
        case .closeFollowingTabs: String(localized: "Close tabs after the current tab in sidebar order. Favorite records are kept.")
        case .newGroup: String(localized: "Create a group containing the current tab and choose its name.")
        case .moveToGroup: String(localized: "Choose a group for the current tab.")
        case .moveToSpace: String(localized: "Move the current tab to another space.")
        case .nextSpace, .previousSpace: String(localized: "Switch spaces in their listed order.")
        }
    }

    var symbol: String {
        switch self {
        case .zoomIn: "plus.magnifyingglass"
        case .zoomOut: "minus.magnifyingglass"
        case .resetZoom: "1.magnifyingglass"
        case .reloadFromOrigin: "arrow.clockwise"
        case .stopLoading: "xmark"
        case .printPage: "printer"
        case .showDownloads: "arrow.down.circle"
        case .nextTab: "arrow.right"
        case .previousTab: "arrow.left"
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
        case .closeOtherTabs: "xmark"
        case .closeFollowingTabs: "xmark"
        case .newGroup: "folder.badge.plus"
        case .moveToGroup: "folder"
        case .moveToSpace: "square.stack"
        case .nextSpace: "chevron.forward"
        case .previousSpace: "chevron.backward"
        case .newTab: "plus"
        case .openLocation: "magnifyingglass"
        case .commandPalette: "command"
        case .back: "arrow.left"
        case .forward: "arrow.right"
        case .reload: "arrow.clockwise"
        case .closeTab: "xmark"
        case .reopenTab: "arrow.uturn.backward"
        case .toggleSidebar: "sidebar.left"
        case .newProfile: "person.badge.plus"
        case .newSpace: "plus.square"
        case .profiles: "person.crop.circle"
        case .passwords: "key"
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
        case .profiles, .newProfile, .passwords: .profiles
        case .newSpace, .nextSpace, .previousSpace: .spaces
        case .reload, .reloadFromOrigin, .stopLoading, .zoomIn, .zoomOut, .resetZoom, .printPage,
             .findInPage, .findNext, .findPrevious, .copyLink, .controlCenter, .clearCookies, .clearCache, .siteSettings: .page
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
