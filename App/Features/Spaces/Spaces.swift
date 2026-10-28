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

    /// Moves tabs to another space, asking first when that changes their profile. `destination` places them there,
    /// as a drop does; otherwise each keeps its kind of place, at the end. `showing` is shown once it arrives.
    func moveTabs(_ ids: [UUID], toSpace spaceID: UUID, at destination: TabDestination? = nil, showing: UUID? = nil) {
        transfer(TabTransfer(items: ids.map(PinnedItem.tab), spaceID: spaceID, destination: destination, showing: showing))
    }

    /// Moves groups, with their tabs, and tabs to another space: groups at the end of its pinned list, tabs each to the
    /// end of their kind of place.
    func moveEntries(_ items: [PinnedItem], toSpace spaceID: UUID) {
        transfer(TabTransfer(items: items, spaceID: spaceID))
    }

    /// Moves groups and tabs, in their order, into a space's pinned list before `targetID`, or last.
    func movePinned(_ items: [PinnedItem], toSpace spaceID: UUID, before targetID: UUID?, showing: UUID? = nil) {
        if items.allSatisfy({ owningSpace(of: $0) == spaceID }) {
            for item in items where item.id != targetID {
                switch item {
                case .tab(let id): moveTab(id, to: .list(group: nil), before: targetID)
                case .group(let id): if !isChangingStructure, session.moveGroup(id: id, before: targetID) { persist() }
                }
            }
            window.tabSelection.clear()
        } else {
            transfer(TabTransfer(items: items, spaceID: spaceID, pinned: true, before: targetID, showing: showing))
        }
    }

    /// Asks first when any tab changes profile, a group's included.
    private func transfer(_ transfer: TabTransfer) {
        guard !isChangingStructure, let target = session.spaces.first(where: { $0.id == transfer.spaceID }) else { return }
        var held = transfer
        held.items = transfer.items.filter { owningSpace(of: $0).map { $0 != transfer.spaceID } ?? false }
        guard !held.items.isEmpty else { return }
        let tabs = tabs(tabIDs(of: held.items))
        if tabs.contains(where: { profileID(of: $0) != target.profileID }) {
            present(.transferTabs(held))
        } else { transferTabs(held) }
    }

    /// All or none: a tab still downloading keeps every tab where it is. A group goes with its tabs.
    func transferTabs(_ transfer: TabTransfer) {
        guard !isChangingStructure else { return }
        let affected = tabIDs(of: transfer.items)
        guard !affected.contains(where: downloads.isDownloading(from:)) else {
            structureFailure(String(localized: "Wait for this space’s downloads to finish.")); return
        }
        let moved = relocate(affected) {
            var moved: [UUID: UUID] = [:]
            for item in transfer.items {
                switch item {
                case .group(let id):
                    moved.merge(session.transferGroup(id: id, to: transfer.spaceID, before: transfer.before) ?? [:]) { $1 }
                case .tab(let id):
                    // A pane brings its split along.
                    let arrived = session.transfer(id: id, to: transfer.spaceID)
                    moved.merge(arrived) { $1 }
                    if transfer.pinned, let tab = arrived[id] { _ = session.move(id: tab, to: .list(group: nil), before: transfer.before) }
                }
            }
            return moved
        }
        if let destination = transfer.destination {
            moveTabs(transfer.items.compactMap { if case .tab(let id) = $0 { moved[id] } else { nil } }, to: destination.place, before: destination.before)
        }
        window.tabSelection.clear()
        if let shown = transfer.showing.flatMap({ moved[$0] }), transfer.spaceID == window.selectedSpaceID { selectTab(shown) }
    }

    private func owningSpace(of item: PinnedItem) -> UUID? {
        switch item {
        case .tab(let id): session.tabs.first { $0.id == id }?.spaceID
        case .group(let id): session.spaces.first { $0.groups.contains { $0.id == id } }?.id
        }
    }

    /// Every tab the items carry: the tabs, and each group's.
    func tabIDs(of items: [PinnedItem]) -> [UUID] {
        items.flatMap { item -> [UUID] in
            switch item {
            case .tab(let id): session.split(containing: id)?.tabIDs ?? [id]
            case .group(let id): session.tabs.filter { $0.place == .list(group: id) }.map(\.id)
            }
        }
    }

    /// Runs `move`, which gives each tab's identity in its new space, the same within a profile, a new one across
    /// profiles, then lets go of what an old identity held. A tab shown here hands over to the next one.
    private func relocate(_ ids: [UUID], _ move: () -> [UUID: UUID]) -> [UUID: UUID] {
        let originals = tabs(ids)
        let shown = originals.first { $0.id == window.selectedTabID }
        let next = shown.flatMap { tabShown(afterRemoving: $0, along: Set(ids)) }
        let moved = move()
        for tab in originals {
            guard let id = moved[tab.id] else { continue }
            if id != tab.id {
                pages.close(tabID: tab.id)
                openedFavorites.remove(tab.id)
                recentTabs.removeAll { $0 == tab.id }
                if let oldProfile = session.spaces.first(where: { $0.id == tab.spaceID })?.profileID {
                    extensions.extensionsIfMade(for: oldProfile)?.didCloseTab(tab.id)
                }
                if let arrived = session.tabs.first(where: { $0.id == id }) { extensionsDidOpen(arrived) }
            }
            lastSelection[tab.spaceID] = nil
        }
        persist()
        if shown != nil { selectTab(next) }
        return moved
    }
}

/// Tabs, or groups with theirs, on their way to another space, held while the person confirms a change of profile.
struct TabTransfer {
    /// In their order.
    var items: [PinnedItem]
    let spaceID: UUID
    /// Where the tabs land, as a drop places them; otherwise each keeps its kind of place, at the end.
    var destination: TabDestination? = nil
    /// Everything lands in the pinned list, before `before` or last. Groups always go there.
    var pinned = false
    var before: UUID? = nil
    var showing: UUID? = nil
}
