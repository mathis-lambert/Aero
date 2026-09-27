public enum BrowserCommand: String, CaseIterable, Sendable {
    case newTab, openLocation, commandPalette, back, forward, reload, closeTab, reopenTab, toggleSidebar, profiles, newProfile, newSpace
    case showHistory, findInPage, findNext, findPrevious, copyLink, controlCenter, clearCookies, clearCache, siteSettings

    case zoomIn, zoomOut, resetZoom, reloadFromOrigin, stopLoading, printPage, showDownloads
    case nextTab, previousTab, recentTab, previousRecentTab
    case tab1, tab2, tab3, tab4, tab5, tab6, tab7, tab8, lastTab
    case toggleFavorite, duplicateTab, renameTab, closeOtherTabs, closeFollowingTabs
    case newGroup, moveToGroup, moveToSpace, nextSpace, previousSpace

    /// Who receives the command's shortcut while a web page has keyboard focus.
    public enum KeyRouting: Sendable {
        /// The browser always acts, so a page can never trap the user.
        case reserved
        /// The page may handle the shortcut; the browser acts only if it does not.
        case pageFirst
    }

    /// Mirrors Safari: tab, navigation and history shortcuts are reserved; the control bar and find
    /// use shortcuts web applications and editors commonly claim.
    public var keyRouting: KeyRouting {
        switch self {
        case .commandPalette, .findInPage, .findNext, .findPrevious, .copyLink,
             .profiles, .controlCenter, .clearCookies, .clearCache, .siteSettings, .stopLoading: .pageFirst
        default: .reserved
        }
    }
}
