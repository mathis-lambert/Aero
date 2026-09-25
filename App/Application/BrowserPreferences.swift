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

/// Application preferences are separate from profiles and browsing records.
@MainActor @Observable
final class BrowserPreferences {
    private enum Key {
        static let testSuitePrefix = "app.getaero.browser.tests."
        static let language = "browser.language"
        static let appleLanguages = "AppleLanguages"
        static let hibernationEnabled = "browser.hibernation.enabled"
        static let hibernationIdleMinutes = "browser.hibernation.idleMinutes"
        static let hibernationKeepsPinned = "browser.hibernation.keepsPinnedTabsLoaded"
        static let appIcon = "browser.appIcon"
    }

    private let defaults: UserDefaults
    private let launchLanguage: BrowserLanguage
    private(set) var language: BrowserLanguage
    var hibernation: HibernationSettings {
        didSet { storeHibernation() }
    }
    /// `nil` is Automatic: the bundle icon, which follows the appearance.
    var appIcon: AppIconVariant? {
        didSet { defaults.set(appIcon?.id, forKey: Key.appIcon) }
    }
    var needsLanguageRestart: Bool { language != launchLanguage }

    init(testNamespace: String?) {
        if let testNamespace {
            defaults = UserDefaults(suiteName: Key.testSuitePrefix + testNamespace) ?? .standard
        } else { defaults = .standard }
        let language = defaults.string(forKey: Key.language).flatMap(BrowserLanguage.init(rawValue:)) ?? .system
        self.language = language
        launchLanguage = language
        hibernation = Self.loadHibernation(from: defaults)
        appIcon = defaults.string(forKey: Key.appIcon).flatMap(AppIconVariant.init(id:))
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
