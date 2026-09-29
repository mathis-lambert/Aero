import Foundation

/// The adapter for Chromium browsers: each profile becomes an Aero profile with one space in its name and color,
/// with its favorites when the browser keeps them readable, its history and the icons of its favorites. Arc builds
/// its spaces from its sidebar and reuses the rest (`ArcImport`).
enum ChromiumImport {
    static func read(_ profiles: [ChromiumProfile], limits: ImportLimits) -> [ImportedProfile] {
        profiles.enumerated().map { index, profile in
            var space = ImportedSpace()
            // Dia's favorites are encrypted; its `Bookmarks` file holds leftovers it does not show.
            if profile.browser.favorites == .bookmarks,
               let bookmarks = try? ChromiumBookmarks.read(Data(contentsOf: profile.file("Bookmarks")), limits: limits) {
                space = bookmarks
            }
            space.name = profile.name
            space.color = profile.color
            space.position = index
            return imported(profile, spaces: [space], limits: limits)
        }
    }

    /// A profile with the given spaces, its history, and the icons it has for their favorites. A profile without
    /// history or icons still imports its favorites.
    static func imported(_ profile: ChromiumProfile, spaces: [ImportedSpace], limits: ImportLimits) -> ImportedProfile {
        let history = (try? ChromiumHistory.read(profile.file("History"), limits: limits)) ?? ImportedHistory()
        let icons = (try? ChromiumFavicons.read(profile.file("Favicons"), for: spaces.flatMap(\.allLinks).map(\.url))) ?? [:]
        return ImportedProfile(id: profile.id, name: profile.name, spaces: spaces, history: history, icons: icons)
    }
}
