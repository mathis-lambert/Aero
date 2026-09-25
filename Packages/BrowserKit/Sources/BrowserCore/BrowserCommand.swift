public enum BrowserCommand: String, CaseIterable, Sendable {
    case newTab, openLocation, commandPalette, back, forward, reload, closeTab, reopenTab, toggleSidebar, profiles
    case showHistory, findInPage, findNext, findPrevious

    /// Who receives the command's shortcut while a web page has keyboard focus.
    public enum KeyRouting: Sendable {
        /// The browser always acts, so a page can never trap the user.
        case reserved
        /// The page may handle the shortcut; the browser acts only if it does not.
        case pageFirst
    }

    /// Mirrors Safari: tab, navigation and history shortcuts are reserved; the palette and find
    /// use shortcuts web applications and editors commonly claim.
    public var keyRouting: KeyRouting {
        switch self {
        case .newTab, .openLocation, .back, .forward, .reload, .closeTab, .reopenTab, .showHistory: .reserved
        case .commandPalette, .toggleSidebar, .profiles, .findInPage, .findNext, .findPrevious: .pageFirst
        }
    }
}
