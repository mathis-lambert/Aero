import Foundation

// Reading another browser's favorites and history. See docs/ONBOARDING.md › Import. Readers take their folders as
// parameters and never write to them; open tabs are never read.

/// A browser found on this Mac. Finding it lists folders only.
public struct ImportSource: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case chromium(ChromiumBrowser)
        case safari
    }

    /// Where the source's spaces and favorites come from.
    public enum Favorites: Hashable, Sendable {
        /// Arc's sidebar file: spaces, pinned tabs, folders and favorites.
        case spaces
        /// Bookmarks: one space per profile.
        case bookmarks
        /// The browser keeps them encrypted, which no other app can read: none come, and the onboarding says so (Dia).
        case unreadable
    }

    public let kind: Kind
    /// The browser's folder: a Chromium user data folder, or Safari's.
    public let root: URL
    /// A Chromium browser's profiles; Safari has none.
    public let profiles: [ChromiumProfile]
    /// False when macOS denies access (Safari without Full Disk Access).
    public let isReadable: Bool

    public var id: String { root.path }

    public var name: String {
        switch kind {
        case .chromium(let browser): browser.name
        case .safari: "Safari"
        }
    }

    public var shortName: String {
        switch kind {
        case .chromium(let browser): browser.shortName
        case .safari: "Safari"
        }
    }

    public var bundleIdentifier: String {
        switch kind {
        case .chromium(let browser): browser.bundleIdentifier
        case .safari: "com.apple.Safari"
        }
    }

    public var favorites: Favorites {
        switch kind {
        case .chromium(let browser): browser.favorites
        case .safari: .bookmarks
        }
    }

    /// Safari keeps its passwords in the Passwords app, which no other app can read.
    public var importsPasswords: Bool { kind != .safari }
}

public enum BrowserImport {
    /// Installed browsers, in the order of `ChromiumBrowser.all`, then Safari.
    public static func sources(applicationSupport: URL, safari: URL) -> [ImportSource] {
        var sources = ChromiumBrowser.all.compactMap { browser -> ImportSource? in
            let root = browser.root(in: applicationSupport), profiles = browser.profiles(in: applicationSupport)
            let found = browser.favorites == .spaces
                ? FileManager.default.fileExists(atPath: root.deletingLastPathComponent().appendingPathComponent(ArcImport.sidebarFile).path)
                : !profiles.isEmpty
            return found ? ImportSource(kind: .chromium(browser), root: root, profiles: profiles, isReadable: true) : nil
        }
        var isFolder: ObjCBool = false
        if FileManager.default.fileExists(atPath: safari.path, isDirectory: &isFolder), isFolder.boolValue {
            let readable = FileManager.default.isReadableFile(atPath: safari.appendingPathComponent("Bookmarks.plist").path)
                && (try? FileManager.default.contentsOfDirectory(atPath: safari.path)) != nil
            sources.append(ImportSource(kind: .safari, root: safari, profiles: [], isReadable: readable))
        }
        return sources
    }

    /// The source's profiles with their spaces, history and icons, through its adapter. Blocking: call it off the main actor.
    public static func read(_ source: ImportSource, limits: ImportLimits) throws -> [ImportedProfile] {
        guard source.isReadable else { throw BrowserImportError.accessDenied }
        switch source.kind {
        case .chromium(let browser) where browser.favorites == .spaces:
            return try ArcImport.read(browser: browser, root: source.root, profiles: source.profiles, limits: limits)
        case .chromium: return ChromiumImport.read(source.profiles, limits: limits)
        case .safari: return try SafariImport.read(root: source.root, limits: limits)
        }
    }
}
