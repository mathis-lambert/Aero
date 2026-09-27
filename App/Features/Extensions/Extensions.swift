import AppKit
import BrowserCore
import BrowserWebKit
import Foundation
import os
import WebKit

/// What an extension asks the person to accept: its installation, an update, or more permissions.
struct ExtensionRequest {
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

    func installedExtensions(inProfile profileID: UUID) -> [InstalledExtension] {
        session.profiles.first { $0.id == profileID }?.extensions.filter { !$0.isRemoving } ?? []
    }

    func startExtensions() {
        extensionsTask = Task { [weak self] in
            await self?.restoreExtensions()
            while !Task.isCancelled {
                await self?.updateExtensions()
                do { try await Task.sleep(for: Self.updateInterval) } catch { return }
            }
        }
    }

    /// Reconcile durable removal intents before loading enabled extensions.
    private func restoreExtensions() async {
        for profile in session.profiles where !profile.isRemoving {
            for record in profile.extensions {
                if record.isRemoving { await finishRemoving(record, inProfile: profile.id) }
                else if record.isEnabled { await load(record, inProfile: profile.id) }
            }
            if let recoveryPackages {
                let retained = Set((session.profiles.first { $0.id == profile.id }?.extensions ?? []).map(\.packageID)).union(recoveryPackages)
                do { try await pages.removeUnusedExtensionPackages(inProfile: profile.id, keeping: retained) }
                catch { Self.logger.error("Could not clean unused extension packages") }
            }
        }
        extensionsReady = true
    }

    func installFromWebStore(_ identifier: String, inProfile profileID: UUID, inSettings: Bool = false) async {
        guard beginExtensionOperation(identifier, profileID: profileID) else { return }
        defer { endExtensionOperation(identifier, profileID: profileID) }
        do {
            let package = try await WebStore.package(identifier)
            let candidate = try await pages.extensions(for: profileID).prepare(crx: package, identifier: identifier)
            await review(candidate, source: .webStore, inProfile: profileID, inSettings: inSettings)
        } catch { extensionFailure() }
    }

    /// The store page's own button, in place of its grey Add to Chrome.
    func page(_ tabID: UUID, webStoreButtonAt url: URL) -> WebStoreButton? {
        guard let identifier = WebStore.extensionID(on: url), let tab = tab(tabID),
              let profileID = profileID(of: tab) else { return nil }
        return installedExtensions(inProfile: profileID).contains { $0.id == identifier }
            ? WebStoreButton(title: String(localized: "Added to Aero"), isEnabled: false)
            : WebStoreButton(title: String(localized: "Add to Aero"), isEnabled: true)
    }

    func page(_ tabID: UUID, didPressWebStoreButtonAt url: URL) async {
        guard let identifier = WebStore.extensionID(on: url), let tab = tab(tabID),
              let profileID = profileID(of: tab) else { return }
        await installFromWebStore(identifier, inProfile: profileID)
    }

    func installFromFolder(_ folder: URL, inProfile profileID: UUID) async {
        guard beginExtensionOperation("folder-import", profileID: profileID) else { return }
        defer { endExtensionOperation("folder-import", profileID: profileID) }
        do {
            let candidate = try await pages.extensions(for: profileID).prepare(folder: folder)
            guard beginExtensionOperation(candidate.identifier, profileID: profileID) else {
                await discard(candidate, inProfile: profileID)
                return
            }
            defer { endExtensionOperation(candidate.identifier, profileID: profileID) }
            await review(candidate, source: .folder(folder), inProfile: profileID, inSettings: true)
        } catch { extensionFailure() }
    }

    /// Folder reloads are reviewed too: their permissions may have changed.
    func reloadExtension(_ record: InstalledExtension, inProfile profileID: UUID) async {
        guard case .folder(let folder) = record.source, beginExtensionOperation(record.id, profileID: profileID) else { return }
        defer { endExtensionOperation(record.id, profileID: profileID) }
        do {
            let candidate = try await pages.extensions(for: profileID).prepare(folder: folder)
            await review(candidate, source: record.source, inProfile: profileID, inSettings: true)
        } catch { extensionFailure() }
    }

    func setEnabled(_ enabled: Bool, _ record: InstalledExtension, inProfile profileID: UUID) async {
        guard beginExtensionOperation(record.id, profileID: profileID) else { return }
        defer { endExtensionOperation(record.id, profileID: profileID) }
        let previous = record
        var record = record
        record.isEnabled = enabled
        guard await commitExtension(record, id: record.id, inProfile: profileID) else { return }
        do {
            if enabled { try await pages.extensions(for: profileID).load(record) }
            else { try pages.extensions(for: profileID).unload(record.id) }
        } catch {
            await commitExtension(previous, id: record.id, inProfile: profileID)
            extensionFailure()
        }
    }

    func setPinned(_ pinned: Bool, _ record: InstalledExtension, inProfile profileID: UUID) async {
        guard beginExtensionOperation(record.id, profileID: profileID) else { return }
        defer { endExtensionOperation(record.id, profileID: profileID) }
        var record = record
        record.isPinned = pinned
        await commitExtension(record, id: record.id, inProfile: profileID)
    }

    func removeExtension(_ record: InstalledExtension, inProfile profileID: UUID) async {
        guard beginExtensionOperation(record.id, profileID: profileID, allowsRemovalRetry: true) else { return }
        defer { endExtensionOperation(record.id, profileID: profileID) }
        var removing = record
        removing.isRemoving = true
        guard await commitExtension(removing, id: record.id, inProfile: profileID) else { return }
        await finishRemoving(removing, inProfile: profileID)
    }

    private func finishRemoving(_ record: InstalledExtension, inProfile profileID: UUID) async {
        do {
            try await pages.extensions(for: profileID).remove(record)
            await commitExtension(nil, id: record.id, inProfile: profileID)
        } catch { extensionFailure() }
    }

    private func review(_ candidate: ProfileExtensions.Candidate, source: InstalledExtension.Source, inProfile profileID: UUID,
                        inSettings: Bool) async {
        let webExtension = candidate.webExtension
        let permissions = webExtension.requestedPermissions.map(\.rawValue).sorted()
        let sites = webExtension.allRequestedMatchPatterns.map(\.string).sorted()
        let previous = installedExtensions(inProfile: profileID).first { $0.id == candidate.identifier }
        let accepted = await ask(previous == nil ? .installation : .update, name: webExtension.displayName ?? candidate.identifier,
                                 icon: webExtension.icon(for: Self.reviewIconSize), permissions: permissions, sites: sites, inSettings: inSettings)
        guard accepted else { await discard(candidate, inProfile: profileID); return }
        var record = previous ?? InstalledExtension(id: candidate.identifier, version: "", source: source, grantedPermissions: [], grantedSites: [])
        record.source = source
        record.version = webExtension.version ?? ""
        record.packageID = candidate.packageID
        record.grantedPermissions = permissions
        record.grantedSites = sites
        record.pendingVersion = nil
        await activate(record, previous: previous, inProfile: profileID)
    }

    private func activate(_ record: InstalledExtension, previous: InstalledExtension?, inProfile profileID: UUID) async {
        guard await commitExtension(record, id: record.id, inProfile: profileID) else { return }
        guard record.isEnabled else { return }
        do { try await pages.extensions(for: profileID).load(record) }
        catch {
            // Keep the previous immutable package available and restore its committed registration.
            if await commitExtension(previous, id: record.id, inProfile: profileID), let previous, previous.isEnabled {
                await load(previous, inProfile: profileID)
            }
            extensionFailure()
        }
    }

    private func load(_ record: InstalledExtension, inProfile profileID: UUID) async {
        do { try await pages.extensions(for: profileID).load(record) }
        catch { extensionFailure() }
    }

    private func updateExtensions() async {
        for profile in session.profiles {
            for saved in profile.extensions {
                guard let record = installedExtensions(inProfile: profile.id).first(where: { $0.id == saved.id }),
                      record.source == .webStore, record.pendingVersion == nil,
                      beginExtensionOperation(record.id, profileID: profile.id) else { continue }
                defer { endExtensionOperation(record.id, profileID: profile.id) }
                let owner = pages.extensions(for: profile.id)
                // Automatic checks are best effort; unavailable updates retry on the next cycle.
                guard let version = try? await WebStore.newerVersion(of: record.id, than: record.version),
                      let package = try? await WebStore.package(record.id),
                      let candidate = try? await owner.prepare(crx: package, identifier: record.id) else { continue }
                var updated = record
                if Set(candidate.webExtension.requestedPermissions.map(\.rawValue)).isSubset(of: record.grantedPermissions),
                   Set(candidate.webExtension.allRequestedMatchPatterns.map(\.string)).isSubset(of: record.grantedSites) {
                    updated.version = candidate.webExtension.version ?? version
                    updated.packageID = candidate.packageID
                    await activate(updated, previous: record, inProfile: profile.id)
                } else {
                    await discard(candidate, inProfile: profile.id)
                    updated.pendingVersion = version
                    await commitExtension(updated, id: record.id, inProfile: profile.id)
                }
            }
        }
    }

    func extensionOperationInProgress(_ id: String, profileID: UUID) -> Bool {
        extensionOperations.contains(profileID.uuidString + ":" + id)
    }

    private func beginExtensionOperation(_ id: String, profileID: UUID, allowsRemovalRetry: Bool = false) -> Bool {
        guard extensionsReady, !isChangingStructure, session.profiles.contains(where: { $0.id == profileID && !$0.isRemoving }) else { return false }
        let removing = session.profiles.first { $0.id == profileID }?.extensions.contains { $0.id == id && $0.isRemoving } == true
        guard !removing || allowsRemovalRetry else { return false }
        return extensionOperations.insert(profileID.uuidString + ":" + id).inserted
    }

    private func endExtensionOperation(_ id: String, profileID: UUID) { extensionOperations.remove(profileID.uuidString + ":" + id) }

    private func discard(_ candidate: ProfileExtensions.Candidate, inProfile profileID: UUID) async {
        // Unreferenced candidates are also collected on the next launch.
        do { try await pages.extensions(for: profileID).discard(candidate) }
        catch { Self.logger.error("Could not remove unused extension candidate") }
    }

    private func extensionFailure() {
        present(.error(String(localized: "The extension operation could not be completed. Your saved files have been kept. Try again.")))
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

    func tabIDs(inProfile profileID: UUID) -> [UUID] {
        let spaces = Set(session.spaces.filter { $0.profileID == profileID }.map(\.id))
        return session.tabs.filter { spaces.contains($0.spaceID) }.map(\.id)
    }

    func selectedTabID(inProfile profileID: UUID) -> UUID? { profile?.id == profileID ? window.selectedTabID : nil }

    func tab(_ tabID: UUID) -> BrowserTab? { session.tabs.first { $0.id == tabID } }

    func openTab(_ url: URL, inProfile profileID: UUID, selected: Bool) -> UUID? {
        guard !isChangingStructure, let space = destinationSpace(for: profileID), let tab = addTab(url, in: space.id) else { return nil }
        if selected, profile?.id == profileID { selectTab(tab.id) }
        return tab.id
    }

    func activate(tabID: UUID) {
        guard let tab = tab(tabID), !isChangingStructure else { return }
        showTab(tab)
    }

    func close(tabID: UUID) { closeTab(tabID) }

    var windowFrame: CGRect { WindowConfiguration.mainWindow?.frame ?? .null }

    func requestPermissions(_ permissions: Set<String>, sites: Set<String>, for extensionID: String, inProfile profileID: UUID) async -> Bool {
        guard var record = installedExtensions(inProfile: profileID).first(where: { $0.id == extensionID }) else { return false }
        guard beginExtensionOperation(extensionID, profileID: profileID) else { return false }
        defer { endExtensionOperation(extensionID, profileID: profileID) }
        let webExtension = pages.extensions(for: profileID).contexts[extensionID]?.webExtension
        guard await ask(.permissions, name: webExtension?.displayName ?? extensionID, icon: webExtension?.icon(for: Self.reviewIconSize),
                        permissions: permissions.sorted(), sites: sites.sorted()) else { return false }
        record.grantedPermissions = Array(Set(record.grantedPermissions).union(permissions)).sorted()
        record.grantedSites = Array(Set(record.grantedSites).union(sites)).sorted()
        return await commitExtension(record, id: record.id, inProfile: profileID)
    }

    /// Anchored to the extension's button when it shows, otherwise to the control center's.
    func presentPopup(_ popover: NSPopover, for extensionID: String) {
        window.controlCenterPresented = false
        guard let anchor = window.extensionAnchors.object(forKey: extensionID as NSString)
                ?? window.extensionAnchors.object(forKey: ExtensionAnchor.controlCenter as NSString) else { return }
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }
}
