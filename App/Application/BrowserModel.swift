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

    init() {
        launchInterval = Self.signposter.beginInterval(Diagnostics.Signpost.launch)
        let environment = ProcessInfo.processInfo.environment
        let testing = environment["AURO_TEST_DATA"]
            .map { URL(fileURLWithPath: $0).lastPathComponent }
        preferences = BrowserPreferences(testNamespace: testing)
        let folder: URL
        if let testing {
            // Resolve inside this application's sandbox, not the UI test runner's container.
            folder = URL.temporaryDirectory.appendingPathComponent("AuroTests", isDirectory: true)
                .appendingPathComponent(testing, isDirectory: true)
        }
        else {
            let support = URL.applicationSupportDirectory
            #if DEBUG
            folder = support.appendingPathComponent("Auro Development", isDirectory: true)
            #else
            folder = support.appendingPathComponent("Auro", isDirectory: true)
            #endif
        }
        store = SessionStore(directory: folder)
        pages = WebPageRegistry(ephemeral: testing != nil, hibernation: preferences.hibernation)
        pages.isPinned = { [weak self] id in self?.session.tabs.first { $0.id == id }?.isPinned == true }
    }

    var profile: BrowserProfile? { session.profiles.first { $0.id == window.selectedProfileID } }
    var space: BrowserSpace? { session.spaces.first { $0.profileID == window.selectedProfileID } }
    var tabs: [BrowserTab] { session.tabs.filter { $0.spaceID == space?.id } }
    var selectedTab: BrowserTab? { tabs.first { $0.id == window.selectedTabID } }
    var canReopen: Bool { closedTabs.contains { $0.spaceID == space?.id } }

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
    }

    private func endLaunchInterval() {
        guard let launchInterval else { return }
        Self.signposter.endInterval(Diagnostics.Signpost.launch, launchInterval)
        self.launchInterval = nil
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
        guard session.profiles.contains(where: { $0.id == id }) else { return }
        if let profileID = window.selectedProfileID { lastSelection[profileID] = window.selectedTabID }
        window.selectedProfileID = id
        window.commandBar = nil
        selectTab(lastSelection[id])
    }

    func selectTab(_ id: UUID?, recordRecent: Bool = true) {
        guard let id, let tab = tabs.first(where: { $0.id == id }), let profileID = window.selectedProfileID else {
            window.selectedTabID = nil
            currentPage = nil
            pages.deactivate()
            return
        }
        window.selectedTabID = id
        if recordRecent { recentTabs.removeAll { $0 == id }; recentTabs.insert(id, at: 0) }
        currentPage = pages.activate(tab, profileID: profileID) { [weak self] url, title in
            guard let self, let existing = self.session.tabs.first(where: { $0.id == id }),
                  existing.url != url || existing.title != title else { return }
            self.session.updateTab(id: id, url: url, title: title)
            self.persist()
        } onOpen: { [weak self] url in
            // Popups inherit the originating profile/space, even after switching profiles.
            self?.open(url, in: tab.spaceID)
        }
    }

    func open(_ url: URL, in destination: UUID? = nil) {
        guard NavigationInput.isWebURL(url), let spaceID = destination ?? space?.id,
              let tab = session.open(url, in: spaceID) else { return }
        if spaceID == space?.id { selectTab(tab.id) }
        persist()
    }

    func submit(_ input: String, replacing: Bool) {
        do {
            let url = try NavigationInput.resolve(input)
            if replacing, let id = window.selectedTabID, let currentPage {
                session.updateTab(id: id, url: url, title: "")
                currentPage.load(url)
                persist()
            } else { open(url) }
            window.commandBar = nil
        } catch { errorMessage = String(localized: "Enter a website address or a search. Only HTTP and HTTPS addresses can be opened.") }
    }

    func closeTab(_ id: UUID) {
        let oldTabs = tabs
        guard let tab = session.close(id: id) else { return }
        pages.close(tabID: id)
        closedTabs.append(tab)
        if closedTabs.count > Self.maximumClosedTabs { closedTabs.removeFirst() }
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

    func setHibernation(_ settings: HibernationSettings) {
        preferences.hibernation = settings
        pages.hibernationSettings = settings
    }

    func saveProfile(id: UUID?, name: String, color: ProfileColor) -> Bool {
        do {
            if let id { try session.editProfile(id: id, name: name, color: color) }
            else {
                let created = try session.addProfile(name: name, color: color)
                switchProfile(created.id)
            }
            persist()
            return true
        } catch {
            errorMessage = String(format: String(localized: "Choose a profile name between 1 and %d characters."), BrowserProfile.maximumNameLength)
            return false
        }
    }

    func setAppearance(_ appearance: BrowserAppearance) { session.appearance = appearance; persist() }

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

struct CommandBarRequest: Identifiable {
    let id = UUID()
    let replacing: Bool
    let initialText: String
}
