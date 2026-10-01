import AppKit
import BrowserCore
import Foundation
import WebKit

/// Owns the profiles' extension runtimes and package directories. The app owns durable registrations.
@MainActor
public final class ExtensionRegistry {
    public weak var host: ExtensionHost?
    private var profiles: [UUID: ProfileExtensions] = [:]
    /// Developer mode: backgrounds, popups, windows and offscreen documents can be inspected, and extensions add
    /// their developer tools panels to Web Inspector (`devtools_page`).
    public var isInspectable = false {
        didSet { for profile in profiles.values { profile.inspectabilityDidChange() } }
    }
    private let folder: URL
    private let nativeHostFolders: [URL]
    private let ephemeral: Bool
    private let dataStore: (UUID) -> WKWebsiteDataStore
    private let idle = IdleMonitor()
    private var focusObservers: [any NSObjectProtocol] = []
    /// The system's last answer on notifications, compared when Aero becomes active again.
    private var notificationsAllowed: Bool?
    private var notificationCheck: Task<Void, Never>?

    /// `folder` holds each profile's prepared packages; `nativeHostFolders` are searched for native messaging hosts,
    /// in order; `dataStore` is the profile's website data store, which its extensions share with its pages.
    public init(folder: URL, nativeHostFolders: [URL], ephemeral: Bool, dataStore: @escaping (UUID) -> WKWebsiteDataStore) {
        self.folder = folder
        self.nativeHostFolders = nativeHostFolders
        self.ephemeral = ephemeral
        self.dataStore = dataStore
        // Contexts use Chrome's origins, so match patterns may name them.
        WKWebExtension.MatchPattern.registerCustomURLScheme("chrome-extension")
        idle.onChange = { [weak self] in self?.profiles.values.forEach { $0.idleStateDidChange() } }
        let center = NotificationCenter.default
        focusObservers = [
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.focusDidChange() }
            },
            center.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.focusDidChange() }
            },
            // The person may have changed Aero's notifications in System Settings meanwhile.
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.checkNotificationsAllowed() }
            }
        ]
    }

    isolated deinit {
        notificationCheck?.cancel()
        for profile in profiles.values { profile.close() }
        for observer in focusObservers { NotificationCenter.default.removeObserver(observer) }
    }

    public func extensions(for profileID: UUID) -> ProfileExtensions {
        if let existing = profiles[profileID] { return existing }
        let created = ProfileExtensions(profileID: profileID, folder: packagesFolder(profileID), nativeHostFolders: nativeHostFolders,
                                        store: dataStore(profileID), ephemeral: ephemeral, idle: idle, registry: self)
        profiles[profileID] = created
        return created
    }

    /// Reads an existing runtime without creating one for a view or tab event.
    public func extensionsIfMade(for profileID: UUID) -> ProfileExtensions? { profiles[profileID] }

    // MARK: - Pages

    /// Attaches the profile's controller and isolated store-button script before page creation.
    public func configure(_ configuration: WKWebViewConfiguration, forProfile profileID: UUID) {
        configuration.webExtensionController = extensions(for: profileID).controller
        WebStore.addButton(to: configuration.userContentController, profileID: profileID, registry: self)
    }

    /// An extension's own page needs its context's configuration.
    public func configuration(forExtensionPage url: URL, inProfile profileID: UUID) -> WKWebViewConfiguration? {
        extensions(for: profileID).controller.extensionContext(for: url)?.webViewConfiguration
    }

    public func allowsWebsiteReturn(to target: URL, from origin: URL, inProfile profileID: UUID) -> Bool {
        guard let context = profiles[profileID]?.controller.extensionContext(for: target), context.isLoaded else { return false }
        return ExtensionResources.allows(target, from: origin, context: context)
    }

    public func menuItems(forTab tabID: UUID, inProfile profileID: UUID) -> [NSMenuItem] {
        profiles[profileID]?.menuItems(forTab: tabID) ?? []
    }

    /// Watches for idleness only while an extension of some profile listens for it.
    func updateIdleInterest() {
        idle.watch(intervals: profiles.values.flatMap(\.idleInterest))
    }

    // MARK: - Notifications

    private func checkNotificationsAllowed() {
        guard notificationCheck == nil, let host,
              profiles.values.contains(where: { $0.listensForNotificationPermission }) || notificationsAllowed == nil else { return }
        notificationCheck = Task { [weak self] in
            let allowed = await host.notificationsAllowed()
            guard let self, !Task.isCancelled else { return }
            self.notificationCheck = nil
            defer { self.notificationsAllowed = allowed }
            guard let previous = self.notificationsAllowed, previous != allowed else { return }
            for profile in self.profiles.values { profile.notificationsAllowedDidChange(allowed) }
        }
    }

    // MARK: - Focus

    private func focusDidChange() {
        for profile in profiles.values { profile.focusDidChange() }
    }

    // MARK: - Removal

    private func packagesFolder(_ profileID: UUID) -> URL { folder.appendingPathComponent(profileID.uuidString, isDirectory: true) }

    /// Only unreferenced package directories are disposable; recovery references also retain packages.
    public func removeUnusedPackages(inProfile profileID: UUID, keeping identifiers: Set<UUID>) async throws {
        let folder = packagesFolder(profileID)
        try await Task.detached {
            guard FileManager.default.fileExists(atPath: folder.path) else { return }
            for child in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
                if let id = UUID(uuidString: child.lastPathComponent), identifiers.contains(id) { continue }
                try FileManager.default.removeItem(at: child)
            }
        }.value
    }

    /// Called only after all spaces have left the profile and the deletion intent has committed, before its website
    /// data store is removed.
    public func removeProfile(_ profileID: UUID, extensions records: [InstalledExtension]) async throws {
        if !records.isEmpty {
            let owner = extensions(for: profileID)
            for record in records { try await owner.remove(record) }
        }
        profiles.removeValue(forKey: profileID)?.close()
        let folder = packagesFolder(profileID)
        try await Task.detached {
            if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
        }.value
    }
}
