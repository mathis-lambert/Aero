import BrowserCore
import Foundation
import Observation
import SwiftUI

enum BrowserLanguage: String, CaseIterable, Identifiable {
    case system, english, french
    var id: Self { self }
    var localeIdentifier: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .french: "fr"
        }
    }
    var label: LocalizedStringKey {
        switch self {
        case .system: "System language"
        case .english: "English"
        case .french: "Français"
        }
    }
}

enum BrowserAppearance: String, Identifiable {
    case system, light, dark
    var id: Self { self }
    /// `nil` follows the system.
    var nativeAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
    var label: LocalizedStringKey {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

/// Application preferences are separate from profiles and browsing records.
@MainActor @Observable
final class BrowserPreferences {
    private enum Key {
        static let testSuitePrefix = "app.getaero.browser.tests."
        static let language = "browser.language"
        static let appearance = "browser.appearance"
        static let searchEngine = "browser.searchEngine"
        static let searchSuggestions = "browser.searchSuggestions"
        static let confirmsQuit = "browser.confirmsQuit"
        static let appleLanguages = "AppleLanguages"
        static let hibernationEnabled = "browser.hibernation.enabled"
        static let hibernationIdleMinutes = "browser.hibernation.idleMinutes"
        static let hibernationKeepsPinned = "browser.hibernation.keepsPinnedTabsLoaded"
        static let appIcon = "browser.appIcon"
        static let blocksAds = "browser.blocksAds"
        static let automaticPictureInPicture = "browser.automaticPictureInPicture"
        static let filterListsCheckedAt = "browser.filterLists.checkedAt"
    }

    private let defaults: UserDefaults
    private let launchLanguage: BrowserLanguage
    private(set) var language: BrowserLanguage
    var appearance: BrowserAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: Key.appearance) }
    }
    var searchEngine: SearchEngine {
        didSet { defaults.set(searchEngine.rawValue, forKey: Key.searchEngine) }
    }
    var searchSuggestions: Bool {
        didSet { defaults.set(searchSuggestions, forKey: Key.searchSuggestions) }
    }
    /// Whether ⌘Q asks before quitting.
    var confirmsQuit: Bool {
        didSet { defaults.set(confirmsQuit, forKey: Key.confirmsQuit) }
    }
    var hibernation: HibernationSettings {
        didSet { storeHibernation() }
    }
    /// `nil` is Automatic: the running icon follows the app’s effective appearance.
    var appIcon: AppIconVariant? {
        didSet { defaults.set(appIcon?.id, forKey: Key.appIcon) }
    }
    /// Sites without their own decision follow these two.
    var blocksAds: Bool {
        didSet { defaults.set(blocksAds, forKey: Key.blocksAds) }
    }
    var automaticPictureInPicture: Bool {
        didSet { defaults.set(automaticPictureInPicture, forKey: Key.automaticPictureInPicture) }
    }
    /// When ad blocking last asked for newer lists, whatever the answer.
    var filterListsCheckedAt: Date? {
        didSet { defaults.set(filterListsCheckedAt, forKey: Key.filterListsCheckedAt) }
    }
    var needsLanguageRestart: Bool { language != launchLanguage }

    init(testNamespace: String?) {
        if let testNamespace {
            // Never the person's own preferences.
            guard let suite = UserDefaults(suiteName: Key.testSuitePrefix + testNamespace) else { preconditionFailure("No preferences suite for the test run") }
            defaults = suite
        } else { defaults = .standard }
        let language = defaults.string(forKey: Key.language).flatMap(BrowserLanguage.init(rawValue:)) ?? .system
        self.language = language
        launchLanguage = language
        appearance = defaults.string(forKey: Key.appearance).flatMap(BrowserAppearance.init(rawValue:)) ?? .system
        searchEngine = defaults.string(forKey: Key.searchEngine).flatMap(SearchEngine.init(rawValue:)) ?? .default
        searchSuggestions = defaults.object(forKey: Key.searchSuggestions) as? Bool ?? true
        confirmsQuit = defaults.object(forKey: Key.confirmsQuit) as? Bool ?? true
        hibernation = Self.loadHibernation(from: defaults)
        appIcon = defaults.string(forKey: Key.appIcon).flatMap(AppIconVariant.init(id:))
        blocksAds = defaults.object(forKey: Key.blocksAds) as? Bool ?? true
        automaticPictureInPicture = defaults.object(forKey: Key.automaticPictureInPicture) as? Bool ?? true
        filterListsCheckedAt = defaults.object(forKey: Key.filterListsCheckedAt) as? Date
    }

    func setLanguage(_ language: BrowserLanguage) {
        self.language = language
        defaults.set(language.rawValue, forKey: Key.language)
        // Apple's bundle localization is resolved at launch. Persist a per-app language
        // override instead of swapping bundles or partially translating a running UI.
        if let identifier = language.localeIdentifier { defaults.set([identifier], forKey: Key.appleLanguages) }
        else { defaults.removeObject(forKey: Key.appleLanguages) }
    }

    private static func loadHibernation(from defaults: UserDefaults) -> HibernationSettings {
        var settings = HibernationSettings.default
        if defaults.object(forKey: Key.hibernationEnabled) != nil {
            settings.isEnabled = defaults.bool(forKey: Key.hibernationEnabled)
        }
        let limit = HibernationSettings.minute * defaults.integer(forKey: Key.hibernationIdleMinutes)
        if HibernationSettings.idleLimitOptions.contains(limit) { settings.idleLimit = limit }
        settings.keepsPinnedTabsLoaded = defaults.bool(forKey: Key.hibernationKeepsPinned)
        return settings
    }

    private func storeHibernation() {
        defaults.set(hibernation.isEnabled, forKey: Key.hibernationEnabled)
        defaults.set(Int(hibernation.idleLimit / HibernationSettings.minute), forKey: Key.hibernationIdleMinutes)
        defaults.set(hibernation.keepsPinnedTabsLoaded, forKey: Key.hibernationKeepsPinned)
    }
}
