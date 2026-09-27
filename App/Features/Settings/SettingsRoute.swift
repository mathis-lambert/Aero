import Foundation

/// Settings history includes detail pages, not only sidebar sections.
enum SettingsRoute: Hashable {
    case section(SettingsSection)
    case profile(UUID)
    case space(UUID)

    var section: SettingsSection {
        switch self {
        case .section(let section): section
        case .profile: .profiles
        case .space: .spaces
        }
    }
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, tabs, profiles, spaces, extensions, shortcuts
    var id: Self { self }
    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .tabs: String(localized: "Tabs")
        case .profiles: String(localized: "Profiles")
        case .spaces: String(localized: "Spaces")
        case .extensions: String(localized: "Extensions")
        case .shortcuts: String(localized: "Shortcuts")
        }
    }
    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .tabs: "square.on.square"
        case .profiles: "person.crop.circle"
        case .spaces: "square.stack"
        case .extensions: "puzzlepiece.extension"
        case .shortcuts: "keyboard"
        }
    }
}
