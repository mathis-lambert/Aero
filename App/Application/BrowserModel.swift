import AppKit
import BrowserCore
import BrowserStorage
import BrowserWebKit
import Foundation
import Observation
import os

@MainActor @Observable
final class BrowserModel {
    private static let maximumClosedTabs = 20
    private static let signposter = OSSignposter(subsystem: Diagnostics.subsystem, category: Diagnostics.Category.launch)
    private static var saveFailureMessage: String {
        String(localized: "Changes could not be saved. Check that there is enough disk space and try again.")
    }
    var session = BrowserSession(profileName: String(localized: "Personal"), spaceName: String(localized: "Main"))
    private(set) var isReady = false
    private(set) var loadFailed = false
    let window = BrowserWindowState()
    private let appIcon: AppIcon
    let preferences: BrowserPreferences
    let favicons: FaviconCache
    let history: BrowserHistory
    let passwords: Passwords
    let suggestionFetcher = SuggestionFetcher()
    private let filterLists: FilterListUpdater?
    @ObservationIgnored var extensionsTask: Task<Void, Never>?
    var currentPage: BrowserPage?
    /// The first launch's onboarding while it shows (docs/ONBOARDING.md).
    private(set) var onboarding: OnboardingModel?
    /// Explicitly opened favorites, including hibernated and internal pages. Runtime only.
    var openedFavorites: Set<UUID> = []

    let pages: WebPageRegistry
    let store: BrowserStore
    let storageLocation: StorageLocation
    private(set) var storageFailureMessage: String?
    /// This launch finishes a reset: website data stores are removed before any page exists.
    @ObservationIgnored private var isResetting = false
    @ObservationIgnored private var resetFailed = false
    private(set) var canRecoverStorage = false
    private(set) var isOpeningStorage = false
    var isChangingStructure = false
    var extensionsReady = false
    var extensionOperations: Set<String> = []
    var recoveryPackages: Set<UUID>?
    @ObservationIgnored var revision: UInt64 = 0
    @ObservationIgnored private var titleSaveTask: Task<Void, Never>?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private var needsSave = false
    @ObservationIgnored var closedTabs: [BrowserTab] = []
    @ObservationIgnored var lastSelection: [UUID: UUID] = [:]
    @ObservationIgnored var recentTabs: [UUID] = []
    @ObservationIgnored private var cycleTabs: [UUID] = []
    @ObservationIgnored private var cycleIndex = 0
    @ObservationIgnored private var launchInterval: OSSignpostIntervalState?
    /// Test runs only: the fixture server that stands in for every search engine.
    private let searchTestEndpoint: URL?
    /// Test runs use fixture browsers and isolated records, keychain items and network caches.
    let isTestRun: Bool
    /// Where other browsers are looked for: fixture folders in test runs.
    let importSourceRoots: (applicationSupport: URL, safari: URL)
    /// UI tests opt in with `AERO_TEST_ONBOARDING`; other test runs start on the browser.
    private let showsOnboarding: Bool

    init() {
        launchInterval = Self.signposter.beginInterval(Diagnostics.Signpost.launch)
        let environment = ProcessInfo.processInfo.environment
        let testDirectory = environment["AERO_TEST_DATA"].map { URL(fileURLWithPath: $0, isDirectory: true) }
        let testing = testDirectory?.lastPathComponent
        let location = StorageLocation(testDirectory: testDirectory)
        // A reset erases files and preferences before anything reads them (docs/STORAGE.md › Reset).
        let resetting = BrowserPreferences.isResetPending(testNamespace: testing)
        let erased = resetting && Self.eraseForReset(location)
        if erased { BrowserPreferences.erase(testNamespace: testing) }
        preferences = BrowserPreferences(testNamespace: testing)
        NSApp.appearance = preferences.appearance.nativeAppearance
        appIcon = AppIcon(variant: preferences.appIcon)
        searchTestEndpoint = testing == nil ? nil : environment["AERO_TEST_SEARCH"].flatMap(URL.init(string:))
        isTestRun = testing != nil
        showsOnboarding = testing == nil || environment["AERO_TEST_ONBOARDING"] == "1"
        if let testDirectory {
            let root = environment["AERO_TEST_IMPORT_SOURCES"].map { URL(fileURLWithPath: $0, isDirectory: true) }
                ?? testDirectory.appendingPathComponent("ImportSources", isDirectory: true)
            importSourceRoots = (root.appendingPathComponent("Application Support", isDirectory: true), root.appendingPathComponent("Safari", isDirectory: true))
        } else {
            importSourceRoots = (.applicationSupportDirectory, URL.libraryDirectory.appendingPathComponent("Safari", isDirectory: true))
        }
        storageLocation = location
        let folder = location.data
        store = BrowserStore(directory: folder)
        favicons = FaviconCache(store: FaviconStore(directory: location.caches.appendingPathComponent("Favicons", isDirectory: true)))
        history = BrowserHistory(store: HistoryStore(file: folder.appendingPathComponent("History.sqlite")))
        passwords = Passwords(testNamespace: testing)
        // Test runs must never write into the user's Downloads folder.
        let downloadsFolder = testing == nil ? URL.downloadsDirectory : folder.appendingPathComponent("Downloads", isDirectory: true)
        let downloads = DownloadCoordinator(directory: downloadsFolder, fallbackFilename: String(localized: "Download"))
        let contentBlocker = ContentBlocker(directory: location.caches.appendingPathComponent("Content Rules", isDirectory: true))
        // Test runs reach only the hosts a test provides, never the Mac's own.
        let nativeHosts = testing == nil ? NativeMessagingHost.chromeFolders
            : environment["AERO_TEST_NATIVE_HOSTS"].map { [URL(fileURLWithPath: $0, isDirectory: true)] } ?? []
        pages = WebPageRegistry(downloads: downloads, contentBlocker: contentBlocker, extensionsFolder: folder.appendingPathComponent("Extensions", isDirectory: true),
                                nativeHostFolders: nativeHosts, ephemeral: testing != nil, hibernation: preferences.hibernation)
        // Test runs never download from the internet: only the fixture list, when a test provides one.
        let testFilterList = testing == nil ? nil : environment["AERO_TEST_FILTERS"].flatMap(URL.init(string:))
        if let contentBlocker, testing == nil || testFilterList != nil {
            filterLists = FilterListUpdater(blocker: contentBlocker, store: FilterListStore(directory: location.caches.appendingPathComponent("Filter Lists", isDirectory: true)),
                                            preferences: preferences, testSource: testFilterList)
        } else { filterLists = nil }
        isResetting = resetting
        resetFailed = resetting && !erased
        pages.delegate = self
        pages.extensionHost = self
    }

    isolated deinit {
        extensionsTask?.cancel()
        titleSaveTask?.cancel()
        saveTask?.cancel()
    }

    var profile: BrowserProfile? { session.profiles.first { $0.id == space?.profileID } }
    var accent: SpaceColor { space?.color ?? .initial }
    var space: BrowserSpace? { session.spaces.first { $0.id == window.selectedSpaceID } }
    var tabs: [BrowserTab] { space.map(tabs(in:)) ?? [] }
    var selectedTab: BrowserTab? {
        guard let id = window.selectedTabID, let spaceID = space?.id else { return nil }
        return session.tabs.first { $0.id == id && $0.spaceID == spaceID }
    }
    var canReopen: Bool { closedTabs.contains { $0.spaceID == space?.id } }
    var downloads: DownloadCoordinator { pages.downloads }
    var webSearch: WebSearch { WebSearch(engine: preferences.searchEngine, testEndpoint: searchTestEndpoint) }
    /// The browser page shown instead of a website, if the selected tab holds one.
    var internalPage: InternalPage? { selectedTab.flatMap { InternalPage(url: $0.url) } }

    func start() async {
        guard !isReady, !isOpeningStorage else { return }
        isOpeningStorage = true
        defer { isOpeningStorage = false; endLaunchInterval() }
        loadFailed = false
        storageFailureMessage = nil
        do {
            if isResetting {
                isResetting = false
                do { try await pages.removeAllWebsiteData() } catch { resetFailed = true }
            }
            let saved = try await store.load()
            if let saved { session = saved }
            else { try await store.save(session, revision: revision) }
            try await resumeProfileRemovals()
            // Recovery is useful only after validation. Failure never overwrites the old snapshot.
            do {
                recoveryPackages = try await store.createRecoverySnapshot()
            } catch { present(.error(Self.saveFailureMessage)) }
            window.selectedSpaceID = session.spaces.first?.id
            isReady = true
            if resetFailed { present(.error(String(localized: "Aero could not erase everything. Quit and reopen Aero to finish the reset."))) }
            beginOnboardingIfNeeded(freshStore: saved == nil)
        } catch {
            loadFailed = true
            let hasRecovery = await store.hasRecoverySnapshot()
            canRecoverStorage = (error as? StorageError) != .newerVersion && (error as? StorageError) != .inUse && hasRecovery
            switch error as? StorageError {
            case .newerVersion: storageFailureMessage = String(localized: "This data requires a newer version of Aero. Your files have been kept unchanged.")
            case .inUse: storageFailureMessage = String(localized: "Another Aero process is using this data. Quit it, then retry.")
            default: storageFailureMessage = String(localized: "Your saved data could not be opened. Your files have been kept for recovery.")
            }
            return
        }
        appIcon.apply(preferences.appIcon)
        filterLists?.start()
        Task {
            await passwords.start()
            // Passkeys decide which relying parties a page may name with the same list.
            pages.passkeys?.suffixes = passwords.suffixes
        }
        startExtensions()
    }

    func restoreStorage() async {
        guard !isReady, !isOpeningStorage, canRecoverStorage else { return }
        isOpeningStorage = true
        do {
            try await store.restoreRecoverySnapshot()
            isOpeningStorage = false
            await start()
        } catch {
            isOpeningStorage = false
            storageFailureMessage = Self.saveFailureMessage
        }
    }

    func revealStorage() { NSWorkspace.shared.open(storageLocation.data) }

    /// Only a fresh store starts it; an unfinished one resumes on its step.
    private func beginOnboardingIfNeeded(freshStore: Bool) {
        guard showsOnboarding else { return }
        if let progress = preferences.onboarding {
            if !progress.completed { onboarding = OnboardingModel(browser: self, step: progress.step) }
        } else if freshStore, !preferences.hasOnboardingRecord {
            preferences.onboarding = OnboardingProgress(step: .welcome, completed: false)
            onboarding = OnboardingModel(browser: self, step: .welcome)
        }
    }

    func endOnboarding() {
        onboarding = nil
    }

    /// The onboarding's import steps alone, for someone already using Aero (docs/ONBOARDING.md › When it appears).
    func beginImport() {
        guard onboarding == nil else { return }
        onboarding = OnboardingModel(browser: self, step: .source, mode: .importOnly)
    }

    private func endLaunchInterval() {
        guard let launchInterval else { return }
        Self.signposter.endInterval(Diagnostics.Signpost.launch, launchInterval)
        self.launchInterval = nil
    }

    func destinationSpace(for profileID: UUID) -> BrowserSpace? {
        if let space, space.profileID == profileID { return space }
        return session.spaces.first { $0.profileID == profileID }
    }

    func tabs(in space: BrowserSpace) -> [BrowserTab] {
        session.tabs.filter { $0.spaceID == space.id }
    }

    func profileID(of tab: BrowserTab) -> UUID? {
        session.spaces.first { $0.id == tab.spaceID }?.profileID
    }

    /// Icons follow the tab's profile; `url` defaults to the tab's saved address.
    func faviconKey(for tab: BrowserTab, at url: URL? = nil) -> FaviconKey? {
        profileID(of: tab).flatMap { FaviconKey(profileID: $0, url: url ?? tab.url) }
    }

    func persist() {
        guard isReady else { return }
        revision += 1
        needsSave = true
        guard !isChangingStructure else { return }
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in await self?.savePendingChanges() }
    }

    /// One in-flight snapshot; mutations during I/O collapse into the current session.
    private func savePendingChanges() async {
        defer { saveTask = nil }
        while needsSave {
            needsSave = false
            do { try await store.save(session, revision: revision) }
            catch {
                if !needsSave { present(.error(Self.saveFailureMessage)) }
            }
        }
    }

    func waitForPendingSave() async { await saveTask?.value }

    /// Termination waits for the latest snapshot rather than losing a pending asynchronous write.
    func flush() async -> Bool {
        guard !isChangingStructure else { return false }
        guard isReady else { return true }
        titleSaveTask?.cancel(); titleSaveTask = nil
        await saveTask?.value
        revision += 1
        do {
            try await store.save(session, revision: revision)
            try await history.flush()
            return true
        }
        catch {
            present(.error(Self.saveFailureMessage))
            return false
        }
    }

    func switchSpace(_ id: UUID) {
        guard !isChangingStructure, id != window.selectedSpaceID, session.spaces.contains(where: { $0.id == id }) else { return }
        if let spaceID = window.selectedSpaceID, session.spaces.contains(where: { $0.id == spaceID }) { lastSelection[spaceID] = window.selectedTabID }
        window.selectedSpaceID = id
        cycleTabs = []
        cycleIndex = 0
        window.controlBar = nil
        window.siteSettingsPresented = false
        window.controlCenterPresented = false
        window.renaming = nil
        selectTab(lastSelection[id])
    }

    func selectTab(_ id: UUID?, recordRecent: Bool = true) {
        guard let id, let tab = tabs.first(where: { $0.id == id }), let profileID = profile?.id else {
            passwords.closePicker()
            window.find.dismiss()
            window.selectedTabID = nil
            currentPage = nil
            pages.deactivate()
            return
        }
        if tab.isFavorite { openedFavorites.insert(id) }
        passwords.closePicker(unless: id)
        let previous = window.selectedTabID
        if previous != id { window.find.dismiss() }
        window.selectedTabID = id
        if previous != id { extensionsDidSelect(tab, previous: previous) }
        if recordRecent { markRecent(id) }
        if InternalPage(url: tab.url) != nil {
            currentPage = nil
            pages.deactivate()
        } else {
            currentPage = pages.activate(tab, profileID: profileID)
        }
    }

    /// Selects a tab of any profile, switching to it first.
    func showTab(_ tab: BrowserTab) {
        switchSpace(tab.spaceID)
        selectTab(tab.id)
    }

    func open(_ url: URL) {
        guard let spaceID = space?.id, let tab = addTab(url, in: spaceID) else { return }
        selectTab(tab.id)
    }

    /// Selects the space's tab for `page`, or opens one, so a browser page is never duplicated.
    func show(_ page: InternalPage) {
        if let existing = tabs.first(where: { InternalPage(url: $0.url) == page }) { selectTab(existing.id) }
        else { open(page.url) }
        window.inputFocusRequest = UUID()
    }

    /// Loads `url` in an existing tab. Moving to a browser page releases the tab's website;
    /// moving back to a website creates its page on selection.
    func navigate(_ id: UUID, to url: URL) {
        guard !isChangingStructure else { return }
        guard let tab = tabs.first(where: { $0.id == id }), NavigationInput.isTabURL(url) else { return }
        session.updateTab(id: id, url: url, title: "")
        if InternalPage(url: url) != nil { pages.close(tabID: id) }
        else if InternalPage(url: tab.url) == nil, window.selectedTabID == id { currentPage?.load(url) }
        persist()
        selectTab(id)
    }

    /// Adds a tab record without selecting it.
    @discardableResult
    func addTab(_ url: URL, in spaceID: UUID) -> BrowserTab? {
        guard !isChangingStructure else { return nil }
        guard NavigationInput.isTabURL(url), let tab = session.open(url, in: spaceID) else { return nil }
        persist()
        extensionsDidOpen(tab)
        return tab
    }

    /// Late metadata for a closed tab is ignored. Title-only updates are batched separately.
    func updateTab(_ id: UUID, url: URL, title: String) {
        guard let existing = session.tabs.first(where: { $0.id == id }), existing.url != url || existing.title != title else { return }
        session.updateTab(id: id, url: url, title: title)
        extensionsDidUpdate(existing)
        if !title.isEmpty, let profileID = profileID(of: existing) {
            history.updateTitle(title, for: url, profileID: profileID)
        }
        if existing.url != url { persist() }
        else if titleSaveTask == nil {
            titleSaveTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                self?.titleSaveTask = nil
                self?.persist()
            }
        }
    }

    /// Opens what the control bar chose, then closes the bar over the tab.
    func load(_ url: URL, in target: ControlBarTarget) {
        if target == .currentTab, let id = window.selectedTabID { navigate(id, to: url) }
        else { open(url) }
        window.controlBar = nil
    }

    /// Closing a favorite unloads its page and keeps it. An open tab is removed; popups closed by
    /// their page are not offered by Reopen Closed Tab.
    func closeTab(_ id: UUID, rememberForReopen: Bool = true) {
        guard !isChangingStructure else { return }
        guard let tab = session.tabs.first(where: { $0.id == id }) else { return }
        let wasSelected = window.selectedTabID == id
        let next = wasSelected ? tabShown(afterRemoving: tab) : nil
        pages.close(tabID: id)
        passwords.forget(tabID: id)
        openedFavorites.remove(id)
        recentTabs.removeAll { $0 == id }
        if !tab.isFavorite {
            session.close(id: id)
            extensionsDidClose(tab)
            if rememberForReopen {
                closedTabs.append(tab)
                if closedTabs.count > Self.maximumClosedTabs { closedTabs.removeFirst() }
            }
            persist()
        }
        if wasSelected { selectTab(next) }
    }

    func isTabOpen(_ tab: BrowserTab) -> Bool {
        !tab.isFavorite || openedFavorites.contains(tab.id)
    }

    /// Removing a closed favorite deletes its record; an open one becomes an ordinary tab.
    func removeFavorite(_ id: UUID) {
        guard !isChangingStructure else { return }
        guard let tab = session.tabs.first(where: { $0.id == id }), tab.isFavorite else { return }
        if isTabOpen(tab) {
            moveTab(id, to: .open, before: nil)
        } else {
            session.close(id: id)
            extensionsDidClose(tab)
            persist()
        }
    }

    /// The open tab below a removed one, else above; after a favorite, the tab shown before it.
    func tabShown(afterRemoving tab: BrowserTab) -> UUID? {
        if tab.isFavorite {
            let ids = Set(tabs.map(\.id))
            return recentTabs.first { $0 != tab.id && ids.contains($0) }
        }
        let open = tabs.filter { !$0.isFavorite }
        guard let index = open.firstIndex(where: { $0.id == tab.id }) else { return nil }
        if open.indices.contains(index + 1) { return open[index + 1].id }
        return index > 0 ? open[index - 1].id : nil
    }

    func reopenTab() {
        guard !isChangingStructure else { return }
        guard let index = closedTabs.lastIndex(where: { $0.spaceID == space?.id }) else { return }
        let tab = closedTabs.remove(at: index)
        session.restore(tab)
        extensionsDidOpen(tab)
        selectTab(tab.id)
        persist()
    }

    /// Drops never move a tab into another space.
    func moveTab(_ id: UUID, to place: TabPlace, before targetID: UUID?) {
        guard !isChangingStructure else { return }
        let wasFavorite = session.tabs.first { $0.id == id }?.isFavorite
        guard session.move(id: id, to: place, before: targetID) else { return }
        if wasFavorite == false, place.isFavorite { openedFavorites.insert(id) }
        if !place.isFavorite { openedFavorites.remove(id) }
        if wasFavorite != place.isFavorite { pages.refreshHibernationSchedule() }
        persist()
    }

    func duplicateTab(_ id: UUID) {
        guard !isChangingStructure else { return }
        guard let copy = session.duplicate(id: id) else { return }
        extensionsDidOpen(copy)
        persist()
        selectTab(copy.id)
    }

    /// Giving back the shown title leaves the tab named by its page.
    func renameTab(_ id: UUID, to name: String) {
        guard !isChangingStructure else { return }
        guard let tab = session.tabs.first(where: { $0.id == id }), tab.name != nil || name != tab.displayTitle else { return }
        session.rename(id: id, to: name)
        persist()
    }

    /// The group asks for its name at once.
    func newGroup(with tabID: UUID) {
        guard !isChangingStructure else { return }
        guard let spaceID = session.tabs.first(where: { $0.id == tabID })?.spaceID,
              let group = session.addGroup(named: String(localized: "New Group"), in: spaceID) else { return }
        moveTab(tabID, to: .list(group: group.id), before: nil)
        window.renaming = .group(group.id)
    }

    func renameGroup(_ id: UUID, to name: String) {
        guard !isChangingStructure else { return }
        session.renameGroup(id: id, to: name)
        persist()
    }

    func setGroupCollapsed(_ id: UUID, _ collapsed: Bool) {
        guard !isChangingStructure else { return }
        session.setGroupCollapsed(id: id, collapsed)
        persist()
    }

    func removeGroup(_ id: UUID) {
        guard !isChangingStructure else { return }
        session.removeGroup(id: id)
        persist()
    }

    func setAppearance(_ appearance: BrowserAppearance) {
        preferences.appearance = appearance
        NSApp.appearance = appearance.nativeAppearance
    }

    func setAppIcon(_ variant: AppIconVariant?) {
        preferences.appIcon = variant
        appIcon.apply(variant)
    }

    func setHibernation(_ settings: HibernationSettings) {
        preferences.hibernation = settings
        pages.hibernationSettings = settings
    }

    func setDecision(_ decision: SiteDecision?, for permission: SitePermission, at site: CurrentSite) {
        changeDecisions(at: site) { $0.setDecision(decision, for: permission, at: site.origin, profileID: site.profileID) }
    }

    func resetPermissions(at site: CurrentSite) {
        changeDecisions(at: site) { $0.resetPermissions(at: site.origin, profileID: site.profileID) }
    }

    /// A change to the site's blocking reloads its page, which then loads with or without the rules.
    private func changeDecisions(at site: CurrentSite, _ change: (inout BrowserSession) -> Void) {
        guard !isChangingStructure else { return }
        let blocked = decision(for: .ads, at: site.origin, profileID: site.profileID)
        change(&session)
        persist()
        if decision(for: .ads, at: site.origin, profileID: site.profileID) != blocked { currentPage?.reload() }
    }

    /// One prompt at a time: a new one replaces what is shown, refusing a pending extension request.
    func present(_ prompt: WindowPrompt) {
        if isChangingStructure {
            guard case .error = prompt else { return }
        }
        dismissPrompt()
        window.prompt = prompt
    }

    func dismissPrompt() {
        guard !isChangingStructure else { return }
        if case .extensionRequest(let request) = window.prompt { answer(request, accepted: false) }
        window.prompt = nil
    }

    @discardableResult
    func commitExtension(_ record: InstalledExtension?, id: String, inProfile profileID: UUID) async -> Bool {
        guard isReady else { return false }
        let previous = session.profiles.first { $0.id == profileID }?.extensions.first { $0.id == id }
        if let record { session.setExtension(record, profileID: profileID) }
        else { session.removeExtension(id, profileID: profileID) }
        revision += 1
        do {
            try await store.save(session, revision: revision)
            return true
        } catch {
            if let previous { session.setExtension(previous, profileID: profileID) }
            else { session.removeExtension(id, profileID: profileID) }
            persist()
            present(.error(Self.saveFailureMessage))
            return false
        }
    }

    func cycleTab(backwards: Bool) {
        if cycleTabs.isEmpty {
            let allowed = Set(tabs.map(\.id))
            cycleTabs = recentTabs.filter { allowed.contains($0) }
            cycleTabs += tabs.map(\.id).filter { !cycleTabs.contains($0) }
            cycleIndex = window.selectedTabID.flatMap { cycleTabs.firstIndex(of: $0) } ?? 0
        }
        guard !cycleTabs.isEmpty else { return }
        cycleIndex = (cycleIndex + (backwards ? -1 : 1) + cycleTabs.count) % cycleTabs.count
        selectTab(cycleTabs[cycleIndex], recordRecent: false)
    }

    func commitTabCycle() {
        guard !cycleTabs.isEmpty else { return }
        cycleTabs = []
        if let id = window.selectedTabID { markRecent(id) }
    }

    private func markRecent(_ id: UUID) {
        recentTabs.removeAll { $0 == id }
        recentTabs.insert(id, at: 0)
    }
}
