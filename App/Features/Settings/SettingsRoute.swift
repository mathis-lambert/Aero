import BrowserCore
import Foundation

/// Settings history includes detail pages, not only sidebar sections.
enum SettingsRoute: Hashable {
    case section(SettingsSection)
    case profile(UUID)
    case space(UUID)
    case passwordProfile(UUID)
    case passwordLogin(SavedLogin)
    case passwordImport(UUID)

    var section: SettingsSection {
        switch self {
        case .section(let section): section
        case .profile: .profiles
        case .space: .spaces
        case .passwordProfile, .passwordLogin, .passwordImport: .passwords
        }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, tabs, profiles, spaces, passwords, extensions, storage, shortcuts, updates
    var id: Self { self }
    var title: String {
        switch self {
        case .updates: String(localized: "Software Updates")
        case .general: String(localized: "General")
        case .tabs: String(localized: "Tabs")
        case .profiles: String(localized: "Profiles")
        case .spaces: String(localized: "Spaces")
        case .passwords: String(localized: "Passwords")
        case .extensions: String(localized: "Extensions")
        case .storage: String(localized: "Storage")
        case .shortcuts: String(localized: "Shortcuts")
        }
    }
    var symbol: String {
        switch self {
        case .updates: "arrow.triangle.2.circlepath"
        case .general: "gearshape"
        case .tabs: "square.on.square"
        case .profiles: "person.crop.circle"
        case .spaces: "square.stack"
        case .passwords: "key"
        case .extensions: "puzzlepiece.extension"
        case .storage: "internaldrive"
        case .shortcuts: "keyboard"
        }
    }
}
