import BrowserCore
import Foundation
import Observation
import SwiftUI

/// Aero's language: the system's, or one Aero is translated into. It is Apple's per-app language, the one System
/// Settings › General › Language & Region › Applications sets, which the bundle resolves at launch.
struct AppLanguage: Hashable, Identifiable {
    /// `nil` follows the system.
    let identifier: String?
    var id: String { identifier ?? "" }

    static let system = AppLanguage(identifier: nil)
    /// The system's language, then those of the bundle's translations.
    static let choices: [AppLanguage] = [.system] + Bundle.main.localizations.filter { $0 != "Base" }.sorted().map(AppLanguage.init)

    /// A language as it names itself, as System Settings lists it.
    var name: Text {
        guard let identifier else { return Text("System language") }
        let locale = Locale(identifier: identifier)
        return Text(verbatim: locale.localizedString(forIdentifier: identifier)?.capitalized(with: locale) ?? identifier)
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
        static let sidebarWidth = "browser.sidebarWidth"
        static let appearance = "browser.appearance"
        static let searchEngine = "browser.searchEngine"
        static let searchSuggestions = "browser.searchSuggestions"
        static let confirmsQuit = "browser.confirmsQuit"
        static let appleLanguages = "AppleLanguages"
        static let hibernationEnabled = "browser.hibernation.enabled"
        static let hibernationIdleMinutes = "browser.hibernation.idleMinutes"
        static let hibernationKeepsFavorites = "browser.hibernation.keepsFavoritesLoaded"
        static let appIcon = "browser.appIcon"
        static let blocksAds = "browser.blocksAds"
        static let automaticPictureInPicture = "browser.automaticPictureInPicture"
        static let offersToSavePasswords = "browser.passwords.offersToSave"
        static let developerMode = "browser.developerMode"
        static let filterListsCheckedAt = "browser.filterLists.checkedAt"
        static let onboarding = "browser.onboarding"
        static let resetPending = "browser.resetPending"
    }

    let shortcuts: ShortcutPreferences
    private let defaults: UserDefaults
    private let launchLanguage: AppLanguage
    private(set) var language: AppLanguage
    var sidebarWidth: Double {
        didSet { defaults.set(sidebarWidth, forKey: Key.sidebarWidth) }
    }
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
    /// Web Inspector for pages and extensions; on by default in development builds.
    var developerMode: Bool {
        didSet { defaults.set(developerMode, forKey: Key.developerMode) }
    }
    /// Sites without their own Save passwords decision follow it.
    var offersToSavePasswords: Bool {
        didSet { defaults.set(offersToSavePasswords, forKey: Key.offersToSavePasswords) }
    }
    /// When ad blocking last asked for newer lists, whatever the answer.
    var filterListsCheckedAt: Date? {
        didSet { defaults.set(filterListsCheckedAt, forKey: Key.filterListsCheckedAt) }
    }
    var needsLanguageRestart: Bool { language != launchLanguage }
    /// The first launch's progress (docs/ONBOARDING.md › When it appears). `nil` when absent or unreadable:
    /// an unreadable value never brings the onboarding back.
    var onboarding: OnboardingProgress? {
        get {
            guard let value = defaults.dictionary(forKey: Key.onboarding),
                  value["version"] as? Int == OnboardingProgress.version,
                  let step = (value["step"] as? String).flatMap(OnboardingStep.init(rawValue:)),
                  let completed = value["completed"] as? Bool else { return nil }
            return OnboardingProgress(step: step, completed: completed)
        }
        set {
            guard let newValue else { defaults.removeObject(forKey: Key.onboarding); return }
            defaults.set(["version": OnboardingProgress.version, "step": newValue.step.rawValue, "completed": newValue.completed],
                         forKey: Key.onboarding)
        }
    }
    var hasOnboardingRecord: Bool { defaults.object(forKey: Key.onboarding) != nil }

    init(testNamespace: String?) {
        defaults = Self.defaults(testNamespace: testNamespace)
        let domain = Self.domain(testNamespace: testNamespace)
        let savedWidth = defaults.double(forKey: Key.sidebarWidth)
        sidebarWidth = savedWidth.isFinite ? max(BrowserDesign.sidebarWidth, savedWidth) : BrowserDesign.sidebarWidth
        shortcuts = ShortcutPreferences(defaults: defaults)
        let language = AppLanguage(identifier: (defaults.persistentDomain(forName: domain)?[Key.appleLanguages] as? [String])?.first)
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
        offersToSavePasswords = defaults.object(forKey: Key.offersToSavePasswords) as? Bool ?? true
        #if DEBUG
        developerMode = defaults.object(forKey: Key.developerMode) as? Bool ?? true
        #else
        developerMode = defaults.object(forKey: Key.developerMode) as? Bool ?? false
        #endif
        filterListsCheckedAt = defaults.object(forKey: Key.filterListsCheckedAt) as? Date
    }

    private static func defaults(testNamespace: String?) -> UserDefaults {
        guard let testNamespace else { return .standard }
        // Never the person's own preferences.
        guard let suite = UserDefaults(suiteName: Key.testSuitePrefix + testNamespace) else { preconditionFailure("No preferences suite for the test run") }
        return suite
    }

    // MARK: - Reset (docs/STORAGE.md › Reset)

    func markResetPending() { defaults.set(true, forKey: Key.resetPending) }

    static func isResetPending(testNamespace: String?) -> Bool {
        defaults(testNamespace: testNamespace).bool(forKey: Key.resetPending)
    }

    private static func domain(testNamespace: String?) -> String {
        testNamespace.map { Key.testSuitePrefix + $0 } ?? Bundle.main.bundleIdentifier ?? ""
    }

    /// Every preference of this channel or test run, the pending mark included.
    static func erase(testNamespace: String?) {
        UserDefaults.standard.removePersistentDomain(forName: domain(testNamespace: testNamespace))
        defaults(testNamespace: testNamespace).synchronize()
    }

    /// Takes effect at the next launch, rather than partially translating a running app.
    func setLanguage(_ language: AppLanguage) {
        self.language = language
        if let identifier = language.identifier { defaults.set([identifier], forKey: Key.appleLanguages) }
        else { defaults.removeObject(forKey: Key.appleLanguages) }
    }

    private static func loadHibernation(from defaults: UserDefaults) -> HibernationSettings {
        var settings = HibernationSettings.default
        if defaults.object(forKey: Key.hibernationEnabled) != nil {
            settings.isEnabled = defaults.bool(forKey: Key.hibernationEnabled)
        }
        let limit = HibernationSettings.minute * defaults.integer(forKey: Key.hibernationIdleMinutes)
        if HibernationSettings.idleLimitOptions.contains(limit) { settings.idleLimit = limit }
        settings.keepsFavoritesLoaded = defaults.bool(forKey: Key.hibernationKeepsFavorites)
        return settings
    }

    private func storeHibernation() {
        defaults.set(hibernation.isEnabled, forKey: Key.hibernationEnabled)
        defaults.set(Int(hibernation.idleLimit / HibernationSettings.minute), forKey: Key.hibernationIdleMinutes)
        defaults.set(hibernation.keepsFavoritesLoaded, forKey: Key.hibernationKeepsFavorites)
    }
}
