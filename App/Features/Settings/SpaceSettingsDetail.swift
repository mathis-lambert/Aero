import BrowserCore
import SwiftUI

/// Space identity and profile assignment, with automatic persistence.
struct SpaceSettingsDetail: View {
    let browser: BrowserModel
    let spaceID: UUID
    @State private var draft = SpaceDraft()
    @State private var pendingProfile: UUID?
    @State private var pendingAppearance: Task<Void, Never>?

    private var space: BrowserSpace? { browser.session.spaces.first { $0.id == spaceID } }

    var body: some View {
        Form {
            if space != nil {
                Section {
                    SpaceForm(draft: $draft, profiles: browser.profiles,
                              createProfile: { browser.present(.profile(inSettings: true) { id in draft.profileID = id }) }, commitName: saveName)
                        .padding(.vertical, 8)
                }
                Section {
                    Button(role: .destructive) { browser.present(.removeSpace(spaceID, inSettings: true)) } label: { Label("Delete space…", systemImage: "trash") }
                        .disabled(browser.session.spaces.count <= 1)
                        .accessibilityIdentifier("spaces.delete")
                } footer: {
                    Text(browser.session.spaces.count <= 1 ? "Keep at least one space." : "Its tabs and groups will be removed. Profile data will be kept.")
                }
            }
        }
        .disabled(browser.isChangingStructure || !browser.extensionsReady)
        .onAppear { draft = SpaceDraft(space) }
        .onDisappear {
            saveName()
            pendingAppearance?.cancel()
            saveAppearance()
        }
        .onChange(of: draft.color) { _, color in
            pendingAppearance?.cancel()
            guard !color.isPreset else { saveAppearance(); return }
            // The color panel and hex typing change continuously; save once they rest.
            pendingAppearance = Task {
                try? await Task.sleep(for: .milliseconds(300))
                if !Task.isCancelled { saveAppearance() }
            }
        }
        .onChange(of: draft.emoji) { _, _ in saveAppearance() }
        .onChange(of: draft.profileID) { _, id in if let id { chooseProfile(id) } }
        .onChange(of: space?.profileID) { _, id in draft.profileID = id }
        .onChange(of: space == nil) { _, removed in if removed { browser.showSettings(.section(.spaces)) } }
    }

    /// An empty or overlong name reverts.
    private func saveName() {
        guard let space, draft.id == space.id else { return }
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= BrowserSpace.maximumNameLength else { draft.name = space.name; return }
        if name != space.name { browser.renameSpace(spaceID, to: name) }
        draft.name = name
    }

    private func saveAppearance() {
        guard let space, draft.id == space.id, draft.color != space.color || draft.emoji != (space.emoji ?? "") else { return }
        guard draft.emoji.isEmpty || BrowserSpace.emoji(from: draft.emoji) != nil else { return }
        browser.setSpaceAppearance(spaceID, color: draft.color, emoji: draft.emoji)
    }

    private func chooseProfile(_ id: UUID) {
        guard let space, id != space.profileID, pendingProfile == nil else { return }
        if browser.session.tabs.contains(where: { $0.spaceID == spaceID }) {
            pendingProfile = id
            browser.present(.confirmation(Confirmation(id: "spaceProfile.\(spaceID)", title: Text("Change browsing profile?"),
                                                       message: Text("Pages will reload with this profile. Unsaved input may be lost."),
                                                       confirmTitle: "Reload pages", identifier: "spaces.confirmProfile",
                                                       confirm: { reassign(to: id) }, cancel: keepProfile)))
        } else { reassign(to: id) }
    }

    private func reassign(to id: UUID) {
        saveName()
        pendingAppearance?.cancel()
        saveAppearance()
        guard let space else { return }
        var change = SpaceDraft(space)
        change.profileID = id
        pendingProfile = nil
        Task { if !(await browser.saveSpace(change)) { keepProfile() } }
    }

    private func keepProfile() {
        pendingProfile = nil
        draft.profileID = space?.profileID
    }
}
