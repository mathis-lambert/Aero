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
    private(set) var session = BrowserSession(profileName: String(localized: "Personal"))
    private(set) var isReady = false
    private(set) var loadFailed = false
    var errorMessage: String?
    let window = BrowserWindowState()
    let preferences: BrowserPreferences
    let favicons: FaviconCache
    let history: BrowserHistory
    let suggestionFetcher = SuggestionFetcher()
    var currentPage: BrowserPage?

    @ObservationIgnored let pages: WebPageRegistry
    @ObservationIgnored private let store: SessionStore
    @ObservationIgnored private var revision: UInt64 = 0
    @ObservationIgnored private var closedTabs: [BrowserTab] = []
    @ObservationIgnored private var lastSelection: [UUID: UUID] = [:]
    @ObservationIgnored private var recentTabs: [UUID] = []
    @ObservationIgnored private var cycleTabs: [UUID] = []
    @ObservationIgnored private var cycleIndex = 0
    @ObservationIgnored private var launchInterval: OSSignpostIntervalState?
    /// Test runs only: the fixture server that stands in for every search engine.
    @ObservationIgnored private let searchTestEndpoint: URL?

    init() {
        launchInterval = Self.signposter.beginInterval(Diagnostics.Signpost.launch)
        let environment = ProcessInfo.processInfo.environment
        let testing = environment["AERO_TEST_DATA"]
            .map { URL(fileURLWithPath: $0).lastPathComponent }
        preferences = BrowserPreferences(testNamespace: testing)
        searchTestEndpoint = testing == nil ? nil : environment["AERO_TEST_SEARCH"].flatMap(URL.init(string:))
        let folder: URL
        if let testing {
            // Only the namespace comes from the test runner, whose temporary folder is its own.
            folder = URL.temporaryDirectory.appendingPathComponent("AeroTests", isDirectory: true)
                .appendingPathComponent(testing, isDirectory: true)
        }
        else {
            let support = URL.applicationSupportDirectory
            #if DEBUG
            folder = support.appendingPathComponent("Aero Development", isDirectory: true)
            #else
            folder = support.appendingPathComponent("Aero", isDirectory: true)
            #endif
        }
        store = SessionStore(directory: folder)
        favicons = FaviconCache(store: FaviconStore(directory: folder.appendingPathComponent("Favicons", isDirectory: true)))
        history = BrowserHistory(store: HistoryStore(file: folder.appendingPathComponent("History.sqlite")))
        // Test runs must never write into the user's Downloads folder.
        let downloadsFolder = testing == nil ? URL.downloadsDirectory : folder.appendingPathComponent("Downloads", isDirectory: true)
        let downloads = DownloadCoordinator(directory: downloadsFolder, fallbackFilename: String(localized: "Download"))
        pages = WebPageRegistry(downloads: downloads, ephemeral: testing != nil, hibernation: preferences.hibernation)
        pages.delegate = self
    }

    var profile: BrowserProfile? { session.profiles.first { $0.id == window.selectedProfileID } }
    var accent: ProfileColor { profile?.color ?? .terracotta }
    var space: BrowserSpace? { window.selectedProfileID.flatMap(space(of:)) }
    var tabs: [BrowserTab] { space.map(tabs(in:)) ?? [] }
    var selectedTab: BrowserTab? { tabs.first { $0.id == window.selectedTabID } }
    var canReopen: Bool { closedTabs.contains { $0.spaceID == space?.id } }
    var downloads: DownloadCoordinator { pages.downloads }
    var webSearch: WebSearch { WebSearch(engine: preferences.searchEngine, testEndpoint: searchTestEndpoint) }
    /// The browser page shown instead of a website, if the selected tab holds one.
    var internalPage: InternalPage? { selectedTab.flatMap { InternalPage(url: $0.url) } }

    func start() async {
        guard !isReady, !loadFailed else { return }
        do {
            if let saved = try await store.load() { session = saved }
            window.selectedProfileID = session.profiles.first?.id
            isReady = true
            endLaunchInterval()
        } catch {
            loadFailed = true
            errorMessage = String(localized: "Your saved session could not be opened. It has been kept unchanged. Quit the app to inspect or recover it.")
            endLaunchInterval()
        }
        // After the session, so drawing it never delays the first tabs.
        AppIcon.restore(preferences.appIcon)
    }

    private func endLaunchInterval() {
        guard let launchInterval else { return }
        Self.signposter.endInterval(Diagnostics.Signpost.launch, launchInterval)
        self.launchInterval = nil
    }

    func space(of profileID: UUID) -> BrowserSpace? {
        session.spaces.first { $0.profileID == profileID }
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

    private func persist() {
        guard isReady else { return }
        revision += 1
        let snapshot = session
        let number = revision
        Task {
            do { try await store.scheduleSave(snapshot, revision: number) }
            catch { errorMessage = Self.saveFailureMessage }
        }
    }

    /// Termination waits for the latest snapshot rather than losing a pending asynchronous write.
    func flush() async -> Bool {
        guard isReady else { return true }
        revision += 1
        do { try await store.save(session, revision: revision); return true }
        catch {
            errorMessage = Self.saveFailureMessage
            return false
        }
    }

    func switchProfile(_ id: UUID) {
        guard id != window.selectedProfileID, session.profiles.contains(where: { $0.id == id }) else { return }
        if let profileID = window.selectedProfileID { lastSelection[profileID] = window.selectedTabID }
        window.selectedProfileID = id
        window.controlBar = nil
        selectTab(lastSelection[id])
    }

    func selectTab(_ id: UUID?, recordRecent: Bool = true) {
        guard let id, let tab = tabs.first(where: { $0.id == id }), let profileID = window.selectedProfileID else {
            window.find.dismiss()
            window.selectedTabID = nil
            currentPage = nil
            pages.deactivate()
            return
        }
        if window.selectedTabID != id { window.find.dismiss() }
        window.selectedTabID = id
        if recordRecent { recentTabs.removeAll { $0 == id }; recentTabs.insert(id, at: 0) }
        if InternalPage(url: tab.url) != nil {
            currentPage = nil
            pages.deactivate()
        } else {
            currentPage = pages.activate(tab, profileID: profileID)
        }
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
        guard NavigationInput.isTabURL(url), let tab = session.open(url, in: spaceID) else { return nil }
        persist()
        return tab
    }

    /// Late metadata for a closed tab is ignored. A title alone is saved with the next change or on
    /// quit, so a page that animates its title does not rewrite the session.
    func updateTab(_ id: UUID, url: URL, title: String) {
        guard let existing = session.tabs.first(where: { $0.id == id }), existing.url != url || existing.title != title else { return }
        session.updateTab(id: id, url: url, title: title)
        if !title.isEmpty, let profileID = profileID(of: existing) {
            history.updateTitle(title, for: url, profileID: profileID)
        }
        if existing.url != url { persist() }
    }

    /// Drops never move a tab into another space.
    func moveTab(_ id: UUID, before targetID: UUID?, pinned: Bool) {
        guard tabs.contains(where: { $0.id == id }), session.moveTab(id: id, before: targetID, pinned: pinned) else { return }
        pages.refreshHibernationSchedule()
        persist()
    }

    /// Opens what the control bar chose, then closes the bar over the tab.
    func load(_ url: URL, in target: ControlBarTarget) {
        if target == .currentTab, let id = window.selectedTabID { navigate(id, to: url) }
        else { open(url) }
        window.controlBar = nil
    }

    /// Popups closed by their page are not offered by Reopen Closed Tab.
    func closeTab(_ id: UUID, rememberForReopen: Bool = true) {
        let oldTabs = tabs
        guard let tab = session.close(id: id) else { return }
        pages.close(tabID: id)
        if rememberForReopen {
            closedTabs.append(tab)
            if closedTabs.count > Self.maximumClosedTabs { closedTabs.removeFirst() }
        }
        recentTabs.removeAll { $0 == id }
        if window.selectedTabID == id {
            let index = oldTabs.firstIndex(where: { $0.id == id }) ?? 0
            selectTab(tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id)
        }
        persist()
    }

    func reopenTab() {
        guard let index = closedTabs.lastIndex(where: { $0.spaceID == space?.id }) else { return }
        let tab = closedTabs.remove(at: index)
        session.restore(tab)
        selectTab(tab.id)
        persist()
    }

    func togglePin(_ id: UUID) {
        session.togglePin(id: id)
        pages.refreshHibernationSchedule()
        persist()
    }

    func setAppIcon(_ variant: AppIconVariant?) {
        preferences.appIcon = variant
        AppIcon.apply(variant)
    }

    func setHibernation(_ settings: HibernationSettings) {
        preferences.hibernation = settings
        pages.hibernationSettings = settings
    }

    /// `emoji` is already validated by the profile sheet.
    func saveProfile(id: UUID?, name: String, color: ProfileColor, emoji: String?) -> Bool {
        do {
            if let id { try session.editProfile(id: id, name: name, color: color, emoji: emoji) }
            else {
                let created = try session.addProfile(name: name, color: color, emoji: emoji)
                switchProfile(created.id)
            }
            persist()
            return true
        } catch {
            errorMessage = String(localized: "Choose a profile name between 1 and \(BrowserProfile.maximumNameLength) characters.")
            return false
        }
    }

    func cycleTab(backwards: Bool) {
        if cycleTabs.isEmpty {
            let allowed = Set(tabs.map(\.id))
            cycleTabs = recentTabs.filter { allowed.contains($0) }
            cycleTabs += tabs.map(\.id).filter { !cycleTabs.contains($0) }
            cycleIndex = cycleTabs.firstIndex(of: window.selectedTabID ?? UUID()) ?? 0
        }
        guard !cycleTabs.isEmpty else { return }
        cycleIndex = (cycleIndex + (backwards ? -1 : 1) + cycleTabs.count) % cycleTabs.count
        selectTab(cycleTabs[cycleIndex], recordRecent: false)
    }

    func commitTabCycle() {
        guard !cycleTabs.isEmpty else { return }
        cycleTabs = []
        if let id = window.selectedTabID { recentTabs.removeAll { $0 == id }; recentTabs.insert(id, at: 0) }
    }
}
