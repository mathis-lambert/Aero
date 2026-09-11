import BrowserCore
import Foundation
import os
import WebKit

/// Owns live resources. The UI may detach a page without destroying it; idle pages hibernate
/// and are restored from their interaction state when activated again.
@MainActor
public final class WebPageRegistry {
    struct LivePage {
        let page: BrowserPage
        var lastActive: ContinuousClock.Instant
        var lastExemption: ContinuousClock.Instant?
    }

    static let signposter = OSSignposter(subsystem: Diagnostics.subsystem, category: Diagnostics.Category.pageLifecycle)

    public var hibernationSettings: HibernationSettings {
        get { policy.settings }
        set { policy.settings = newValue; refreshHibernationSchedule() }
    }
    /// Pin state stays owned by the session; the registry only reads it when planning.
    public var isPinned: @MainActor (UUID) -> Bool = { _ in false }

    var livePages: [UUID: LivePage] = [:]
    var activeTabID: UUID?
    var policy: HibernationPolicy
    var evaluation: Task<Void, Never>?
    private var hibernatedStates: [UUID: Any] = [:]
    private var stores: [UUID: WKWebsiteDataStore] = [:]
    private var pressureMonitor: MemoryPressureMonitor?
    private let ephemeral: Bool

    public init(
        ephemeral: Bool = false,
        hibernation: HibernationSettings = .default,
        liveBackgroundPageLimit: Int = HibernationPolicy.liveBackgroundPageLimit(forPhysicalMemory: ProcessInfo.processInfo.physicalMemory)
    ) {
        self.ephemeral = ephemeral
        policy = HibernationPolicy(settings: hibernation, liveBackgroundPageLimit: liveBackgroundPageLimit)
        pressureMonitor = MemoryPressureMonitor { [weak self] pressure in
            self?.policy.pressure = pressure
            self?.refreshHibernationSchedule()
        }
    }

    isolated deinit { evaluation?.cancel() }

    public func dataStore(for profileID: UUID) -> WKWebsiteDataStore {
        if let store = stores[profileID] { return store }
        let store = ephemeral ? WKWebsiteDataStore.nonPersistent() : WKWebsiteDataStore(forIdentifier: profileID)
        stores[profileID] = store
        return store
    }

    public func isLoaded(_ tabID: UUID) -> Bool { livePages[tabID] != nil }

    /// Makes the tab's page visible, creating or restoring it when needed.
    public func activate(
        _ tab: BrowserTab,
        profileID: UUID,
        onMetadata: @escaping @MainActor (URL, String) -> Void,
        onOpen: @escaping @MainActor (URL) -> Void
    ) -> BrowserPage {
        markPreviousActiveAsIdle()
        activeTabID = tab.id
        let page = livePages[tab.id]?.page ?? makePage(for: tab, profileID: profileID, onMetadata: onMetadata, onOpen: onOpen)
        livePages[tab.id] = LivePage(page: page, lastActive: .now)
        refreshHibernationSchedule()
        return page
    }

    public func deactivate() {
        markPreviousActiveAsIdle()
        activeTabID = nil
        refreshHibernationSchedule()
    }

    public func close(tabID: UUID) {
        if activeTabID == tabID { activeTabID = nil }
        hibernatedStates[tabID] = nil
        livePages.removeValue(forKey: tabID)?.page.dispose()
    }

    func hibernate(_ tabID: UUID) {
        guard tabID != activeTabID, let live = livePages.removeValue(forKey: tabID) else { return }
        hibernatedStates[tabID] = live.page.webView.interactionState
        live.page.dispose()
        Self.signposter.emitEvent(Diagnostics.Signpost.pageHibernated)
    }

    private func makePage(
        for tab: BrowserTab,
        profileID: UUID,
        onMetadata: @escaping @MainActor (URL, String) -> Void,
        onOpen: @escaping @MainActor (URL) -> Void
    ) -> BrowserPage {
        let page = BrowserPage(store: dataStore(for: profileID), onMetadata: onMetadata, onOpen: onOpen)
        if let state = hibernatedStates.removeValue(forKey: tab.id) {
            page.restore(state, url: tab.url)
            Self.signposter.emitEvent(Diagnostics.Signpost.pageRestored)
        } else {
            page.load(tab.url)
            Self.signposter.emitEvent(Diagnostics.Signpost.pageCreated)
        }
        return page
    }

    private func markPreviousActiveAsIdle() {
        guard let activeTabID else { return }
        livePages[activeTabID]?.lastActive = .now
    }
}
