import BrowserCore
import Foundation

extension BrowserModel {
    var profiles: [BrowserProfile] { session.profiles.filter { !$0.isRemoving } }

    func createProfile(name: String) async -> UUID? {
        guard extensionsReady, !isChangingStructure, extensionOperations.isEmpty else { return nil }
        isChangingStructure = true
        defer { isChangingStructure = false; persist() }
        do {
            var savedID: UUID?
            try await commitStructure { candidate in
                savedID = try candidate.addProfile(name: name).id
            }
            return savedID
        } catch { structureFailure(); return nil }
    }

    func canRemoveProfile(_ id: UUID) -> Bool {
        profiles.count > 1 && !session.spaces.contains { $0.profileID == id }
    }

    func removeProfile(_ id: UUID) async {
        guard extensionsReady, !isChangingStructure, extensionOperations.isEmpty else { return }
        isChangingStructure = true
        defer { isChangingStructure = false; persist() }
        do {
            try await commitStructure { try $0.markProfileForRemoval(id) }
            try await resumeProfileRemovals()
        } catch { structureFailure() }
    }

    /// A durable intent is also in recovery before any irreversible erase. Retrying is idempotent.
    func resumeProfileRemovals() async throws {
        for profile in session.profiles where profile.isRemoving {
            recoveryPackages = try await store.createRecoverySnapshot()
            try await history.clear(profileID: profile.id, since: nil)
            try await favicons.removeProfile(profile.id)
            try await pages.removeProfile(profile.id, extensions: profile.extensions)
            try session.removeProfile(profile.id)
            revision += 1
            try await store.save(session, revision: revision)
            recoveryPackages = try await store.createRecoverySnapshot()
        }
    }
}
