import AppKit
import BrowserCore
import BrowserWebKit
import Foundation
import os
import WebKit

/// What an extension asks the person to accept: its installation, an update, or more permissions.
struct ExtensionRequest: Identifiable {
    enum Kind { case installation, update, permissions }

    let id = UUID()
    let kind: Kind
    let name: String
    let icon: NSImage?
    let permissions: [String]
    let sites: [String]
    /// Asked from the Settings window, which then shows it.
    let inSettings: Bool
    fileprivate let answer: (Bool) -> Void
}

/// Installing, loading and updating the profiles' extensions. See docs/EXTENSIONS.md.
extension BrowserModel: WebExtensionHost {
    private static let updateInterval = Duration.seconds(24 * 60 * 60)
    private static let logger = Logger(subsystem: Diagnostics.subsystem, category: Diagnostics.Category.extensions)
    private static let reviewIconSize = CGSize(width: 64, height: 64)
    private static var notAnExtension: String { String(localized: "This folder does not hold an extension Aero can load.") }

    func installedExtensions(inProfile profileID: UUID) -> [InstalledExtension] {
        session.profiles.first { $0.id == profileID }?.extensions ?? []
    }

    /// Loads every enabled extension, then checks the store's for updates once a day.
    func startExtensions() async {
        for profile in session.profiles {
            for record in profile.extensions where record.isEnabled { await load(record, inProfile: profile.id) }
        }
        while !Task.isCancelled {
            await updateExtensions()
            do { try await Task.sleep(for: Self.updateInterval) } catch { return }
        }
    }

    /// `inSettings` shows the review in the Settings window it was asked from.
    func installFromWebStore(_ identifier: String, inSettings: Bool = false) async {
        guard let profileID = window.selectedProfileID else { return }
        do {
            let package = try await WebStore.package(identifier)
            let webExtension = try await pages.extensions(for: profileID).prepare(crx: package, identifier: identifier)
            await review(webExtension, identifier: identifier, source: .webStore, inProfile: profileID, inSettings: inSettings)
        } catch {
            errorMessage = String(localized: "The extension could not be installed. Check your connection and try again.")
        }
    }

    func installFromFolder(_ folder: URL) async {
        guard let profileID = window.selectedProfileID else { return }
        do {
            let (identifier, webExtension) = try await pages.extensions(for: profileID).prepare(folder: folder)
            await review(webExtension, identifier: identifier, source: .folder(folder), inProfile: profileID, inSettings: true)
        } catch {
            errorMessage = Self.notAnExtension
        }
    }

    /// Reads a folder extension again, keeping what was granted.
    func reloadExtension(_ record: InstalledExtension, inProfile profileID: UUID) async {
        guard case .folder(let folder) = record.source else { return }
        do {
            _ = try await pages.extensions(for: profileID).prepare(folder: folder)
            await load(record, inProfile: profileID)
        } catch {
            errorMessage = Self.notAnExtension
        }
    }

    func setEnabled(_ enabled: Bool, _ record: InstalledExtension, inProfile profileID: UUID) async {
        var record = record
        record.isEnabled = enabled
        saveExtension(record, inProfile: profileID)
        if enabled { await load(record, inProfile: profileID) } else { pages.extensions(for: profileID).unload(record.id) }
    }

    func setPinned(_ pinned: Bool, _ record: InstalledExtension, inProfile profileID: UUID) {
        var record = record
        record.isPinned = pinned
        saveExtension(record, inProfile: profileID)
    }

    func removeExtension(_ record: InstalledExtension, inProfile profileID: UUID) async {
        deleteExtension(record.id, inProfile: profileID)
        await pages.extensions(for: profileID).remove(record.id)
    }

    /// Shows what the extension asks for; accepting grants exactly that and loads it.
    private func review(_ webExtension: WKWebExtension, identifier: String, source: InstalledExtension.Source, inProfile profileID: UUID,
                        inSettings: Bool) async {
        let permissions = webExtension.requestedPermissions.map(\.rawValue).sorted()
        let sites = webExtension.allRequestedMatchPatterns.map(\.string).sorted()
        let isUpdate = installedExtensions(inProfile: profileID).contains { $0.id == identifier }
        let accepted = await ask(isUpdate ? .update : .installation, name: webExtension.displayName ?? identifier, icon: webExtension.icon(for: Self.reviewIconSize),
                                 permissions: permissions, sites: sites, inSettings: inSettings)
        let extensions = pages.extensions(for: profileID)
        guard accepted else {
            if !installedExtensions(inProfile: profileID).contains(where: { $0.id == identifier }) { await extensions.remove(identifier) }
            return
        }
        var record = installedExtensions(inProfile: profileID).first { $0.id == identifier }
            ?? InstalledExtension(id: identifier, version: "", source: source, grantedPermissions: [], grantedSites: [])
        record.version = webExtension.version ?? ""
        record.grantedPermissions = permissions
        record.grantedSites = sites
        record.pendingVersion = nil
        saveExtension(record, inProfile: profileID)
        await load(record, inProfile: profileID)
    }

    private func load(_ record: InstalledExtension, inProfile profileID: UUID) async {
        do { try await pages.extensions(for: profileID).load(record) }
        catch { Self.logger.error("Could not load extension \(record.id, privacy: .public): \(error.localizedDescription, privacy: .public)") }
    }

    /// An update asking for nothing more is installed; one that asks for more waits for the person.
    private func updateExtensions() async {
        for profile in session.profiles {
            for record in profile.extensions where record.source == .webStore && record.pendingVersion == nil {
                let extensions = pages.extensions(for: profile.id)
                guard let version = try? await WebStore.newerVersion(of: record.id, than: record.version),
                      let package = try? await WebStore.package(record.id),
                      let update = try? await extensions.inspect(crx: package, identifier: record.id) else { continue }
                var updated = record
                if Set(update.requestedPermissions.map(\.rawValue)).isSubset(of: record.grantedPermissions),
                   Set(update.allRequestedMatchPatterns.map(\.string)).isSubset(of: record.grantedSites),
                   (try? await extensions.prepare(crx: package, identifier: record.id)) != nil {
                    updated.version = update.version ?? version
                    if updated.isEnabled { await load(updated, inProfile: profile.id) }
                } else {
                    updated.pendingVersion = version
                }
                saveExtension(updated, inProfile: profile.id)
            }
        }
    }

    private func ask(_ kind: ExtensionRequest.Kind, name: String, icon: NSImage?, permissions: [String], sites: [String], inSettings: Bool = false) async -> Bool {
        guard window.prompt == nil else { return false }
        return await withCheckedContinuation { continuation in
            var answered = false
            let request = ExtensionRequest(kind: kind, name: name, icon: icon, permissions: permissions, sites: sites,
                                           inSettings: inSettings) { [weak self] accepted in
                guard !answered else { return }
                answered = true
                if case .extensionRequest = self?.window.prompt { self?.window.prompt = nil }
                continuation.resume(returning: accepted)
            }
            window.prompt = .extensionRequest(request)
        }
    }

    func answer(_ request: ExtensionRequest, accepted: Bool) { request.answer(accepted) }

    private func extensions(of tab: BrowserTab) -> ProfileExtensions? {
        profileID(of: tab).flatMap(pages.extensionsIfMade(for:))
    }

    func extensionsDidOpen(_ tab: BrowserTab) { extensions(of: tab)?.didOpenTab(tab.id) }
    func extensionsDidClose(_ tab: BrowserTab) { extensions(of: tab)?.didCloseTab(tab.id) }
    func extensionsDidUpdate(_ tab: BrowserTab) { extensions(of: tab)?.didUpdateTab(tab.id) }

    func extensionsDidSelect(_ tab: BrowserTab, previous: UUID?) {
        extensions(of: tab)?.didActivateTab(tab.id, previous: previous.flatMap { id in tabs.contains { $0.id == id } ? id : nil })
    }

    // MARK: - WebExtensionHost

    func tabIDs(inProfile profileID: UUID) -> [UUID] { space(of: profileID).map(tabs(in:))?.map(\.id) ?? [] }

    func selectedTabID(inProfile profileID: UUID) -> UUID? { window.selectedProfileID == profileID ? window.selectedTabID : nil }

    func tab(_ tabID: UUID) -> BrowserTab? { session.tabs.first { $0.id == tabID } }

    func openTab(_ url: URL, inProfile profileID: UUID, selected: Bool) -> UUID? {
        guard let space = space(of: profileID), let tab = addTab(url, in: space.id) else { return nil }
        if selected, window.selectedProfileID == profileID { selectTab(tab.id) }
        return tab.id
    }

    func activate(tabID: UUID) {
        guard let tab = tab(tabID), tab.spaceID == space?.id else { return }
        selectTab(tabID)
    }

    func close(tabID: UUID) { closeTab(tabID) }

    var windowFrame: CGRect { WindowConfiguration.mainWindow?.frame ?? .null }

    func requestPermissions(_ permissions: Set<String>, sites: Set<String>, for extensionID: String) async -> Bool {
        guard let profileID = window.selectedProfileID,
              var record = installedExtensions(inProfile: profileID).first(where: { $0.id == extensionID }) else { return false }
        let webExtension = pages.extensions(for: profileID).contexts[extensionID]?.webExtension
        guard await ask(.permissions, name: webExtension?.displayName ?? extensionID, icon: webExtension?.icon(for: Self.reviewIconSize),
                        permissions: permissions.sorted(), sites: sites.sorted()) else { return false }
        record.grantedPermissions = Array(Set(record.grantedPermissions).union(permissions)).sorted()
        record.grantedSites = Array(Set(record.grantedSites).union(sites)).sorted()
        saveExtension(record, inProfile: profileID)
        return true
    }

    /// Anchored to the extension's button when it shows, otherwise to the control center's.
    func presentPopup(_ popover: NSPopover, for extensionID: String) {
        window.controlCenterPresented = false
        guard let anchor = window.extensionAnchors.object(forKey: extensionID as NSString)
                ?? window.extensionAnchors.object(forKey: ExtensionAnchor.controlCenter as NSString) else { return }
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }
}
