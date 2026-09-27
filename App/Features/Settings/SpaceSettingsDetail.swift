import BrowserCore
import SwiftUI

/// Space identity and profile assignment, with automatic persistence.
struct SpaceSettingsDetail: View {
    let browser: BrowserModel
    let spaceID: UUID
    @State private var draft = SpaceDraft()
    @State private var pendingProfile: UUID?
    @State private var confirmsIdentityChange = false
    @State private var confirmsRemoval = false
    @State private var creatingProfile = false
    @State private var pendingAppearance: Task<Void, Never>?
    @Environment(\.palette) private var palette

    private var space: BrowserSpace? { browser.session.spaces.first { $0.id == spaceID } }

    var body: some View {
        ScrollView {
            if space != nil {
                VStack(alignment: .leading, spacing: 28) {
                    SpaceForm(draft: $draft, profiles: browser.profiles, createProfile: { creatingProfile = true }, commitName: saveName)
                    Hairline()
                    VStack(alignment: .leading, spacing: 8) {
                        Button { confirmsRemoval = true } label: { Label("Delete space…", systemImage: "trash") }
                            .buttonStyle(PanelButtonStyle())
                            .disabled(browser.session.spaces.count <= 1)
                            .accessibilityIdentifier("spaces.delete")
                        Text(browser.session.spaces.count <= 1 ? "Keep at least one space." : "Its tabs and groups will be removed. Profile data will be kept.")
                            .font(BrowserDesign.Typography.caption)
                            .foregroundStyle(palette.secondary)
                    }
                }
                .frame(width: BrowserDesign.formWidth, alignment: .leading)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
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
        .sheet(isPresented: $creatingProfile) {
            ProfilePrompt(browser: browser, usesSheetBackground: true, onCreated: { id in
                creatingProfile = false
                draft.profileID = id
            }, onCancel: { creatingProfile = false })
        }
        .confirmationDialog("Change browsing profile?", isPresented: $confirmsIdentityChange) {
            Button("Reload pages") { if let id = pendingProfile { reassign(to: id) } }
            Button("Cancel", role: .cancel) { keepProfile() }
        } message: { Text("Pages will reload with this profile. Unsaved input may be lost.") }
        .confirmationDialog("Delete space?", isPresented: $confirmsRemoval) {
            Button("Delete space", role: .destructive) {
                Task {
                    await browser.removeSpace(spaceID)
                    if self.space == nil { browser.showSettings(.section(.spaces)) }
                }
            }
        } message: { Text("Its tabs and groups will be removed. Profile data will be kept.") }
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
        guard let space, id != space.profileID, !confirmsIdentityChange else { return }
        if browser.session.tabs.contains(where: { $0.spaceID == spaceID }) {
            pendingProfile = id
            confirmsIdentityChange = true
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
