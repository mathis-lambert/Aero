import BrowserCore
import Foundation

/// Structural changes commit before live pages change identity or external data is erased.
extension BrowserModel {
    func saveSpace(_ draft: SpaceDraft) async -> Bool {
        guard extensionsReady, !isChangingStructure, extensionOperations.isEmpty else { return false }
        isChangingStructure = true
        defer { isChangingStructure = false; persist() }
        let original = session.spaces.first { $0.id == draft.id }
        let changesIdentity = original != nil && (draft.createsProfile || original?.profileID != draft.profileID)
        let affected = original.map(tabs(in:)) ?? []
        if changesIdentity, affected.contains(where: { downloads.isDownloading(from: $0.id) }) {
            structureFailure(String(localized: "Wait for this space’s downloads to finish."))
            return false
        }
        do {
            var savedID: UUID?
            try await commitStructure { candidate in
                let profileID = try draft.createsProfile ? candidate.addProfile(name: draft.profileName).id : draft.profileID
                guard let profileID else { throw SessionError.missingProfile }
                if let id = draft.id {
                    try candidate.editSpace(id: id, name: draft.name, profileID: profileID, color: draft.color, emoji: draft.emoji.isEmpty ? nil : draft.emoji)
                    savedID = id
                } else {
                    savedID = try candidate.addSpace(name: draft.name, profileID: profileID, color: draft.color, emoji: draft.emoji.isEmpty ? nil : draft.emoji).id
                }
            }
            if changesIdentity, let original {
                let replacement = session.tabs.filter { $0.spaceID == original.id }
                let selectedIndex = affected.firstIndex { $0.id == window.selectedTabID }
                for tab in affected {
                    extensions.extensionsIfMade(for: original.profileID)?.didCloseTab(tab.id)
                    pages.close(tabID: tab.id)
                    openedFavorites.remove(tab.id)
                    recentTabs.removeAll { $0 == tab.id }
                }
                for tab in replacement { extensionsDidOpen(tab) }
                closedTabs.removeAll { $0.spaceID == original.id }
                lastSelection[original.id] = nil
                window.controlBar = nil
                window.siteSettingsPresented = false
                window.controlCenterPresented = false
                if original.id == space?.id {
                    selectTab(selectedIndex.flatMap { replacement.indices.contains($0) ? replacement[$0].id : nil })
                }
            }
            if original == nil, let savedID {
                isChangingStructure = false
                switchSpace(savedID)
            }
            return true
        } catch { structureFailure(); return false }
    }

    func removeSpace(_ id: UUID) async {
        guard extensionsReady, !isChangingStructure, extensionOperations.isEmpty else { return }
        isChangingStructure = true
        defer { isChangingStructure = false; persist() }
        let affected = session.tabs.filter { $0.spaceID == id }
        guard !affected.contains(where: { downloads.isDownloading(from: $0.id) }) else {
            structureFailure(String(localized: "Wait for this space’s downloads to finish.")); return
        }
        let oldProfileID = session.spaces.first { $0.id == id }?.profileID
        do {
            try await commitStructure { try $0.removeSpace(id) }
            for tab in affected {
                if let oldProfileID { extensions.extensionsIfMade(for: oldProfileID)?.didCloseTab(tab.id) }
                pages.close(tabID: tab.id)
                openedFavorites.remove(tab.id)
                recentTabs.removeAll { $0 == tab.id }
            }
            closedTabs.removeAll { $0.spaceID == id }
            lastSelection[id] = nil
            if window.selectedSpaceID == id, let next = session.spaces.first {
                isChangingStructure = false
                switchSpace(next.id)
            }
        } catch { structureFailure() }
    }

    func reorderSpace(_ id: UUID, by offset: Int) {
        guard let index = session.spaces.firstIndex(where: { $0.id == id }),
              session.spaces.indices.contains(index + offset) else { return }
        reorderSpaces(from: IndexSet(integer: index), to: index + offset + (offset > 0 ? 1 : 0))
    }

    func reorderSpaces(from offsets: IndexSet, to destination: Int) {
        guard !isChangingStructure else { return }
        session.moveSpaces(from: offsets, to: destination)
        persist()
    }

    func moveTab(_ id: UUID, toSpace spaceID: UUID) {
        guard !isChangingStructure, let tab = session.tabs.first(where: { $0.id == id }),
              let destination = session.spaces.first(where: { $0.id == spaceID }) else { return }
        if profileID(of: tab) != destination.profileID {
            present(.transferTab(id, spaceID))
        } else { transferTab(id, toSpace: spaceID) }
    }

    func transferTab(_ id: UUID, toSpace spaceID: UUID) {
        guard !isChangingStructure, let tab = session.tabs.first(where: { $0.id == id }) else { return }
        guard !downloads.isDownloading(from: id) else {
            structureFailure(String(localized: "Wait for this space’s downloads to finish.")); return
        }
        let oldProfile = profileID(of: tab)
        let wasSelected = window.selectedTabID == id
        let next = wasSelected ? tabShown(afterRemoving: tab) : nil
        guard let moved = session.transfer(id: id, to: spaceID) else { return }
        if moved.id != id {
            pages.close(tabID: id)
            openedFavorites.remove(id)
            recentTabs.removeAll { $0 == id }
            if let oldProfile { extensions.extensionsIfMade(for: oldProfile)?.didCloseTab(id) }
            extensionsDidOpen(moved)
        }
        lastSelection[tab.spaceID] = nil
        persist()
        if wasSelected { selectTab(next) }
    }

}
