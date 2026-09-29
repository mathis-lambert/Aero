import BrowserCore
import BrowserStorage
import Foundation

/// What the person chose to bring over from one source. See docs/ONBOARDING.md › Import.
struct ImportChoice: Equatable {
    var favorites = true
    var history = true
    var passwords = true
}

/// What an import did, per kind; a kind that failed reports why without stopping the others.
struct ImportOutcome: Equatable {
    var spaces = 0
    var favorites = 0
    var historyPages = 0
    var passwords: PasswordImportResult?
    var failure: String?
}

extension BrowserModel {
    /// History pages written per transaction, so progress shows and other history writes are not held up.
    private static let historyBatch = 2000

    /// Lists folders only; cheap enough for the main actor.
    func importSources() -> [ImportSource] {
        BrowserImport.sources(applicationSupport: importSourceRoots.applicationSupport, safari: importSourceRoots.safari)
    }

    /// Reads a source off the main actor.
    nonisolated func readImport(_ source: ImportSource) async throws -> [ImportedProfile] {
        try await Task.detached(priority: .userInitiated) { try BrowserImport.read(source, limits: .standard()) }.value
    }

    /// Applies what was read: profiles, spaces, favorites and groups in one commit, then history in batches and
    /// passwords. `report` receives the outcome as each kind finishes. Importing again adds only what is missing.
    func applyImport(_ profiles: [ImportedProfile], from source: ImportSource, choice: ImportChoice,
                     report: (ImportOutcome) -> Void = { _ in }) async -> ImportOutcome {
        var outcome = ImportOutcome()
        guard !profiles.isEmpty else { return outcome }
        guard !isChangingStructure, extensionOperations.isEmpty else {
            outcome.failure = String(localized: "Aero is busy saving other changes. Try again in a moment.")
            return outcome
        }
        // Source profile ID → Aero profile.
        var destinations: [String: UUID] = [:]
        isChangingStructure = true
        do {
            try await commitStructure { candidate in
                destinations = try Self.merge(profiles, choice: choice, into: &candidate, outcome: &outcome)
            }
            isChangingStructure = false
            persist()
        } catch {
            isChangingStructure = false
            outcome.failure = String(localized: "The favorites could not be saved. Check that there is enough disk space and try again.")
            report(outcome)
            return outcome
        }
        if let first = destinations.values.first, window.selectedSpaceID == nil || !session.spaces.contains(where: { $0.id == window.selectedSpaceID }) {
            switchSpace(destinationSpace(for: first)?.id ?? session.spaces[0].id)
        }
        report(outcome)

        // The source's own icons, so favorites show theirs before their page ever loads.
        if choice.favorites {
            for profile in profiles {
                guard let profileID = destinations[profile.id], !profile.icons.isEmpty else { continue }
                await favicons.adopt(profile.icons, profileID: profileID)
            }
        }

        if choice.history {
            for profile in profiles {
                guard let profileID = destinations[profile.id], !Task.isCancelled else { continue }
                for batch in stride(from: 0, to: profile.history.pages.count, by: Self.historyBatch) {
                    // A profile deleted meanwhile gets no history back.
                    guard session.profiles.contains(where: { $0.id == profileID && !$0.isRemoving }) else { break }
                    let pages = Array(profile.history.pages[batch..<min(batch + Self.historyBatch, profile.history.pages.count)])
                    do {
                        try await history.importPages(pages, profileID: profileID)
                        outcome.historyPages += pages.count
                        report(outcome)
                    } catch {
                        outcome.failure = String(localized: "History could not be saved. Your favorites were imported.")
                        break
                    }
                }
            }
        }

        // Passwords come only from Chromium browsers; test runs never read a real browser's key.
        if choice.passwords, source.importsPasswords, !isTestRun {
            var total = PasswordImportResult()
            for profile in profiles {
                guard let profileID = destinations[profile.id], session.profiles.contains(where: { $0.id == profileID }),
                      let login = source.profiles.first(where: { $0.id == profile.id }), !Task.isCancelled else { continue }
                let result = await importPasswords(from: login, into: profileID)
                total.added += result.added; total.present += result.present; total.skipped += result.skipped
                total.failure = total.failure ?? result.failure
            }
            outcome.passwords = total
            report(outcome)
        }
        return outcome
    }

    /// The model part of an import, applied to a candidate session. The fresh store's untouched default profile and
    /// space take the first imported ones instead of staying empty.
    private static func merge(_ profiles: [ImportedProfile], choice: ImportChoice, into session: inout BrowserSession,
                              outcome: inout ImportOutcome) throws -> [String: UUID] {
        var destinations: [String: UUID] = [:]
        var reusableSpace = session.tabs.isEmpty && session.spaces.count == 1 && session.profiles.count == 1 ? session.spaces.first : nil
        var reusableProfile = reusableSpace.map(\.profileID)

        for profile in profiles {
            let profileID: UUID
            if let reused = reusableProfile {
                try session.editProfile(id: reused, name: name(profile.name, fallback: String(localized: "Imported")))
                profileID = reused
                reusableProfile = nil
            } else if let existing = session.profiles.first(where: { $0.name == name(profile.name, fallback: "") && !$0.isRemoving }) {
                // Importing again lands in the profile the first import created.
                profileID = existing.id
            } else {
                profileID = try session.addProfile(name: name(profile.name, fallback: String(localized: "Imported"))).id
            }
            destinations[profile.id] = profileID
        }
        // Spaces in the order the source shows them, whatever their profile; their favorites only when chosen.
        let spaces = profiles.flatMap { profile in profile.spaces.map { (space: $0, profile: profile) } }.sorted { $0.space.position < $1.space.position }
        for (index, entry) in spaces.enumerated() {
            guard let profileID = destinations[entry.profile.id] else { continue }
            let imported = entry.space
            let spaceName = name(imported.name ?? entry.profile.name, fallback: String(localized: "Imported"))
            let color = imported.color ?? SpaceColor.presets[index % SpaceColor.presets.count].color
            let spaceID: UUID
            // An emoji Aero does not accept leaves the space its initial rather than failing the import.
            let emoji = imported.emoji.flatMap(BrowserSpace.emoji(from:))
            if let reused = reusableSpace {
                try session.editSpace(id: reused.id, name: spaceName, profileID: profileID, color: color, emoji: emoji)
                spaceID = reused.id
                reusableSpace = nil
                outcome.spaces += 1
            } else if let existing = session.spaces.first(where: { $0.name == spaceName && $0.profileID == profileID }) {
                spaceID = existing.id
            } else {
                spaceID = try session.addSpace(name: spaceName, profileID: profileID, color: color, emoji: emoji).id
                outcome.spaces += 1
            }
            if choice.favorites { outcome.favorites += addFavorites(imported, to: spaceID, in: &session) }
        }
        return destinations
    }

    /// Tiles, rows, then collapsed groups; an address already a favorite of the space is not added again.
    private static func addFavorites(_ imported: ImportedSpace, to spaceID: UUID, in session: inout BrowserSession) -> Int {
        var present = Set(session.tabs.filter { $0.spaceID == spaceID && $0.isFavorite }.map(\.url.absoluteString))
        var added = 0
        func add(_ link: ImportedLink, at place: TabPlace) {
            guard present.insert(link.url.absoluteString).inserted, let tab = session.open(link.url, in: spaceID) else { return }
            session.updateTab(id: tab.id, url: link.url, title: link.title)
            _ = session.move(id: tab.id, to: place, before: nil)
            added += 1
        }
        for link in imported.tiles { add(link, at: .grid) }
        for link in imported.links { add(link, at: .list(group: nil)) }
        // Importing again finds the groups it made; two folders with the same name stay two groups.
        var seen: [String: Int] = [:]
        for group in imported.groups {
            let title = switch group.title {
            case .folder(let folder): name(folder, fallback: String(localized: "Folder"))
            case .otherBookmarks: String(localized: "Other bookmarks")
            case .mobileBookmarks: String(localized: "Mobile bookmarks")
            case .bookmarksMenu: String(localized: "Bookmarks menu")
            }
            let occurrence = seen[title, default: 0]
            seen[title] = occurrence + 1
            let existing = session.spaces.first { $0.id == spaceID }?.groups.filter { $0.name == title } ?? []
            guard let groupID = existing.dropFirst(occurrence).first?.id ?? session.addGroup(named: title, in: spaceID)?.id else { continue }
            session.setGroupCollapsed(id: groupID, true)
            for link in group.links { add(link, at: .list(group: groupID)) }
        }
        return added
    }

    /// A valid profile or space name: trimmed, at most the allowed length.
    private static func name(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : String(trimmed.prefix(BrowserProfile.maximumNameLength))
    }
}
