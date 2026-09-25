public enum BrowserCommand: String, CaseIterable, Identifiable, Sendable {
    case newTab, openLocation, commandPalette, back, forward, reload, closeTab, reopenTab, toggleSidebar, profiles
    public var id: Self { self }

    /// Who receives the command's shortcut while a web page has keyboard focus.
    public enum KeyRouting: Sendable {
        /// The browser always acts, so a page can never trap the user.
        case reserved
        /// The page may handle the shortcut; the browser acts only if it does not.
        case pageFirst
    }

    /// Mirrors Safari: tab and navigation shortcuts are reserved; the command palette uses a
    /// shortcut web applications commonly claim.
    public var keyRouting: KeyRouting {
        switch self {
        case .newTab, .openLocation, .back, .forward, .reload, .closeTab, .reopenTab: .reserved
        case .commandPalette, .toggleSidebar, .profiles: .pageFirst
        }
    }
}
