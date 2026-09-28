import BrowserCore
import Foundation

/// A browser built on Chromium: its profiles keep history, passwords and icons the same way. What differs is only
/// where its spaces and favorites come from (`favorites`). See docs/ONBOARDING.md › Sources.
public struct ChromiumBrowser: Hashable, Sendable {
    public let name: String
    public let bundleIdentifier: String
    /// The user data folder, under ~/Library/Application Support.
    let folder: String
    /// The keychain item holding the key its passwords are encrypted with.
    let service: String
    let account: String
    public let favorites: ImportSource.Favorites

    public static let all = [
        ChromiumBrowser(name: "Google Chrome", bundleIdentifier: "com.google.Chrome", folder: "Google/Chrome",
                        service: "Chrome Safe Storage", account: "Chrome", favorites: .bookmarks),
        ChromiumBrowser(name: "Arc", bundleIdentifier: "company.thebrowser.Browser", folder: "Arc/User Data",
                        service: "Arc Safe Storage", account: "Arc", favorites: .spaces),
        ChromiumBrowser(name: "Dia", bundleIdentifier: "company.thebrowser.dia", folder: "Dia/User Data",
                        service: "Dia Safe Storage", account: "Dia", favorites: .unreadable),
        ChromiumBrowser(name: "Brave", bundleIdentifier: "com.brave.Browser", folder: "BraveSoftware/Brave-Browser",
                        service: "Brave Safe Storage", account: "Brave", favorites: .bookmarks),
        ChromiumBrowser(name: "Microsoft Edge", bundleIdentifier: "com.microsoft.edgemac", folder: "Microsoft Edge",
                        service: "Microsoft Edge Safe Storage", account: "Microsoft Edge", favorites: .bookmarks),
        ChromiumBrowser(name: "Vivaldi", bundleIdentifier: "com.vivaldi.Vivaldi", folder: "Vivaldi",
                        service: "Vivaldi Safe Storage", account: "Vivaldi", favorites: .bookmarks)
    ]

    func root(in applicationSupport: URL) -> URL { applicationSupport.appendingPathComponent(folder, isDirectory: true) }

    /// Profile folders holding favorites, history or passwords, with the name and color the browser shows.
    func profiles(in applicationSupport: URL) -> [ChromiumProfile] {
        let root = root(in: applicationSupport)
        guard let children = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        let shown = Self.shownProfiles(in: root)
        return children
            .filter { folder in ChromiumProfile.files.contains { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) } }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { profile($0, shown: shown) }
    }

    /// The profile in `folder` of this browser's user data folder `root`, even when the folder holds no file yet.
    func profile(named folder: String, in root: URL) -> ChromiumProfile {
        profile(root.appendingPathComponent(folder, isDirectory: true), shown: Self.shownProfiles(in: root))
    }

    private func profile(_ folder: URL, shown: [String: (name: String?, color: SpaceColor?)]) -> ChromiumProfile {
        let info = shown[folder.lastPathComponent]
        return ChromiumProfile(browser: self, folder: folder, name: info?.name ?? folder.lastPathComponent, color: info?.color)
    }

    /// `profile.info_cache` in the browser's `Local State`: each folder's name, and its highlight color as a signed ARGB integer.
    private static func shownProfiles(in root: URL) -> [String: (name: String?, color: SpaceColor?)] {
        guard let data = try? Data(contentsOf: root.appendingPathComponent("Local State")),
              let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cache = (state["profile"] as? [String: Any])?["info_cache"] as? [String: Any] else { return [:] }
        return cache.compactMapValues { value in
            guard let entry = value as? [String: Any] else { return nil }
            let color = (entry["profile_highlight_color"] as? Int).map { value -> SpaceColor in
                let argb = UInt32(truncatingIfNeeded: value)
                return SpaceColor(red: UInt8((argb >> 16) & 0xFF), green: UInt8((argb >> 8) & 0xFF), blue: UInt8(argb & 0xFF))
            }
            return (entry["name"] as? String, color)
        }
    }
}

/// One profile of a Chromium browser: its own history, passwords, icons and favorites.
public struct ChromiumProfile: Identifiable, Hashable, Sendable {
    static let files = ["Bookmarks", "History", "Login Data"]

    public let browser: ChromiumBrowser
    let folder: URL
    /// The name the browser shows for the profile.
    public let name: String
    let color: SpaceColor?

    public var id: String { folder.path }
    var folderName: String { folder.lastPathComponent }
    func file(_ name: String) -> URL { folder.appendingPathComponent(name) }
}
