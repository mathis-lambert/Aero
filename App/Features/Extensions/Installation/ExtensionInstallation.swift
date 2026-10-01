import AppKit
import BrowserCore
import BrowserExtensions
import Foundation
import os
import WebKit

/// Installing, loading and updating the profiles' extensions. See docs/EXTENSIONS.md.
extension BrowserModel {
    private static let updateInterval = Duration.seconds(24 * 60 * 60)
    static let extensionLogger = Logger(subsystem: Diagnostics.subsystem, category: Diagnostics.Category.extensions)
    static let reviewIconSize = CGSize(width: 64, height: 64)

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
                do { try await extensions.removeUnusedPackages(inProfile: profile.id, keeping: retained) }
                catch { Self.extensionLogger.error("Could not clean unused extension packages") }
            }
        }
        extensionsReady = true
    }

    func installFromWebStore(_ identifier: String, inProfile profileID: UUID, inSettings: Bool = false) async {
        guard beginExtensionOperation(identifier, profileID: profileID) else { return }
        defer { endExtensionOperation(identifier, profileID: profileID) }
        do {
            let package = try await WebStore.package(identifier)
            let candidate = try await extensions.extensions(for: profileID).prepare(crx: package, identifier: identifier)
            await review(candidate, source: .webStore, inProfile: profileID, inSettings: inSettings)
        } catch { extensionFailure() }
    }

    func installFromFolder(_ folder: URL, inProfile profileID: UUID) async {
        guard beginExtensionOperation("folder-import", profileID: profileID) else { return }
        defer { endExtensionOperation("folder-import", profileID: profileID) }
        do {
            let candidate = try await extensions.extensions(for: profileID).prepare(folder: folder)
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
            let candidate = try await extensions.extensions(for: profileID).prepare(folder: folder)
            await review(candidate, source: record.source, inProfile: profileID, inSettings: true)
        } catch { extensionFailure() }
    }

    /// Starts an extension that could not start again, from its package, keeping its data.
    func restartExtension(_ record: InstalledExtension, inProfile profileID: UUID) async {
        guard record.isEnabled, beginExtensionOperation(record.id, profileID: profileID) else { return }
        defer { endExtensionOperation(record.id, profileID: profileID) }
        await load(record, inProfile: profileID)
    }

    func setEnabled(_ enabled: Bool, _ record: InstalledExtension, inProfile profileID: UUID) async {
        guard beginExtensionOperation(record.id, profileID: profileID) else { return }
        defer { endExtensionOperation(record.id, profileID: profileID) }
        let previous = record
        var record = record
        record.isEnabled = enabled
        guard await commitExtension(record, id: record.id, inProfile: profileID) else { return }
        do {
            if enabled { try await loadApplyingShortcuts(record, inProfile: profileID) }
            else { try extensions.extensions(for: profileID).unload(record.id) }
            extensions.extensions(for: profileID).managementDidChange(enabled ? .enabled : .disabled, of: record.id)
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
            try await extensions.extensions(for: profileID).remove(record)
            guard await commitExtension(nil, id: record.id, inProfile: profileID) else { return }
            shortcuts.forgetExtension(record.id)
            extensions.extensions(for: profileID).managementDidChange(.uninstalled, of: record.id)
        } catch {
            let error = error as NSError
            Self.extensionLogger.error("Extension removal failed: \(error.domain, privacy: .public) \(error.code)")
            extensionFailure()
        }
    }

    private func review(_ candidate: ProfileExtensions.Candidate, source: InstalledExtension.Source, inProfile profileID: UUID,
                        inSettings: Bool) async {
        let webExtension = candidate.webExtension
        let previous = installedExtensions(inProfile: profileID).first { $0.id == candidate.identifier }
        // A new extension that fills websites may take the profile's passwords; a password manager does by default.
        let profileName = session.profiles.first { $0.id == profileID }?.name ?? ""
        let autoFill = previous == nil && candidate.fillsWebsites ? PasswordAutoFillChoice(profileName: profileName, isOn: candidate.managesPasswords) : nil
        let accepted = await ask(previous == nil ? .installation : .update, name: webExtension.displayName ?? candidate.identifier,
                                 icon: webExtension.icon(for: Self.reviewIconSize), permissions: candidate.permissions, sites: candidate.sites,
                                 unavailableFeatures: candidate.unavailableFeatures, passwordAutoFill: autoFill, inSettings: inSettings)
        guard accepted else { await discard(candidate, inProfile: profileID); return }
        var record = previous ?? InstalledExtension(id: candidate.identifier, version: "", source: source, grantedPermissions: [], grantedSites: [])
        record.source = source
        record.version = webExtension.version ?? ""
        record.packageID = candidate.packageID
        record.grantedPermissions = candidate.permissions
        record.grantedSites = candidate.sites
        record.pendingVersion = nil
        await activate(record, previous: previous, inProfile: profileID)
        if autoFill?.isOn == true, passwordExtensionCandidates(inProfile: profileID).contains(where: { $0.id == record.id }) {
            setPasswordExtension(record.id, inProfile: profileID)
        }
    }

    private func activate(_ record: InstalledExtension, previous: InstalledExtension?, inProfile profileID: UUID) async {
        guard await commitExtension(record, id: record.id, inProfile: profileID) else { return }
        guard record.isEnabled else { return }
        do {
            try await loadApplyingShortcuts(record, inProfile: profileID)
            extensions.extensions(for: profileID).managementDidChange(.installed, of: record.id)
        } catch {
            // Keep the previous immutable package available and restore its committed registration.
            if await commitExtension(previous, id: record.id, inProfile: profileID), let previous, previous.isEnabled {
                await load(previous, inProfile: profileID)
            }
            extensionFailure()
        }
    }

    private func load(_ record: InstalledExtension, inProfile profileID: UUID) async {
        do { try await loadApplyingShortcuts(record, inProfile: profileID) }
        catch { extensionFailure() }
    }

    /// Loads the extension, then gives its commands the shortcuts the person chose.
    private func loadApplyingShortcuts(_ record: InstalledExtension, inProfile profileID: UUID) async throws {
        let owner = extensions.extensions(for: profileID)
        try await owner.load(record)
        applyExtensionShortcuts(record.id, in: owner)
    }

    private func updateExtensions() async {
        for profile in session.profiles {
            for saved in profile.extensions {
                guard let record = installedExtensions(inProfile: profile.id).first(where: { $0.id == saved.id }),
                      record.source == .webStore, record.pendingVersion == nil,
                      beginExtensionOperation(record.id, profileID: profile.id) else { continue }
                defer { endExtensionOperation(record.id, profileID: profile.id) }
                let owner = extensions.extensions(for: profile.id)
                // Automatic checks are best effort; unavailable updates retry on the next cycle.
                guard let version = try? await WebStore.newerVersion(of: record.id, than: record.version),
                      let package = try? await WebStore.package(record.id),
                      let candidate = try? await owner.prepare(crx: package, identifier: record.id) else { continue }
                var updated = record
                if Set(candidate.permissions).isSubset(of: record.grantedPermissions), Set(candidate.sites).isSubset(of: record.grantedSites) {
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

    func beginExtensionOperation(_ id: String, profileID: UUID, allowsRemovalRetry: Bool = false) -> Bool {
        guard extensionsReady, !isChangingStructure, session.profiles.contains(where: { $0.id == profileID && !$0.isRemoving }) else { return false }
        let removing = session.profiles.first { $0.id == profileID }?.extensions.contains { $0.id == id && $0.isRemoving } == true
        guard !removing || allowsRemovalRetry else { return false }
        return extensionOperations.insert(profileID.uuidString + ":" + id).inserted
    }

    func endExtensionOperation(_ id: String, profileID: UUID) { extensionOperations.remove(profileID.uuidString + ":" + id) }

    private func discard(_ candidate: ProfileExtensions.Candidate, inProfile profileID: UUID) async {
        // Unreferenced candidates are also collected on the next launch.
        do { try await extensions.extensions(for: profileID).discard(candidate) }
        catch { Self.extensionLogger.error("Could not remove unused extension candidate") }
    }

    private func extensionFailure() {
        present(.error(String(localized: "The extension operation could not be completed. Your saved files have been kept. Try again.")))
    }

    func ask(_ kind: ExtensionRequest.Kind, name: String, icon: NSImage?, permissions: [String] = [], sites: [String] = [],
                     unavailableFeatures: [ExtensionFeature] = [], passwordAutoFill: PasswordAutoFillChoice? = nil, inSettings: Bool = false) async -> Bool {
        guard window.prompt == nil else { return false }
        return await withCheckedContinuation { continuation in
            var answered = false
            let request = ExtensionRequest(kind: kind, name: name, icon: icon, permissions: permissions, sites: sites,
                                           unavailableFeatures: unavailableFeatures, inSettings: inSettings, passwordAutoFill: passwordAutoFill) { [weak self] accepted in
                guard !answered else { return }
                answered = true
                if case .extensionRequest = self?.window.prompt { self?.window.prompt = nil }
                continuation.resume(returning: accepted)
            }
            window.prompt = .extensionRequest(request)
        }
    }

    func answer(_ request: ExtensionRequest, accepted: Bool) { request.answer(accepted) }

}
