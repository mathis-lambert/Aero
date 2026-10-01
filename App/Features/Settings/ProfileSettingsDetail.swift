import BrowserCore
import SwiftUI

/// Laid out like the space form: identity first, then what uses it, then deletion.
struct ProfileSettingsDetail: View {
    let browser: BrowserModel
    let profileID: UUID
    let navigate: (SettingsRoute) -> Void

    var body: some View {
        Form {
            if let profile = browser.profiles.first(where: { $0.id == profileID }) {
                let spaces = browser.session.spaces.filter { $0.profileID == profileID }
                Section {
                    LabeledContent {
                        SettingsNameField(name: profile.name, maximumLength: BrowserProfile.maximumNameLength, identifier: "profiles.name") {
                            browser.renameProfile(profileID, to: $0)
                        }
                    } label: {
                        ProfileMonogram(name: profile.name, size: BrowserDesign.identityHeight)
                    }
                } footer: {
                    Text("Cookies, sign-ins, history, site permissions and extensions stay in this profile. Its spaces share them.")
                }
                Section {
                    if spaces.isEmpty {
                        Text("No spaces use this profile.").foregroundStyle(.secondary)
                    }
                    ForEach(spaces) { space in
                        SettingsRow(title: space.name, open: { navigate(.space(space.id)) }) {
                            SpaceTile(space: space)
                        } subtitle: {
                            Text("\(browser.session.tabs.count { $0.spaceID == space.id }) tabs")
                        } trailing: { EmptyView() }
                    }
                    Button { navigate(.section(.spaces)) } label: { Label("Manage spaces…", systemImage: "square.stack") }
                } header: {
                    Text("Spaces")
                }
                Section {
                    Button(role: .destructive, action: confirmRemoval) { Label("Delete profile…", systemImage: "trash") }
                        .disabled(!browser.canRemoveProfile(profileID))
                        .accessibilityIdentifier("profiles.delete")
                } footer: {
                    Text(removalNote(hasSpaces: !spaces.isEmpty))
                }
            }
        }
        .disabled(browser.isChangingStructure)
    }

    private func confirmRemoval() {
        browser.present(.confirmation(Confirmation(id: "removeProfile.\(profileID)", title: Text("Delete profile and its browsing data?"),
                                                   message: Text("Cookies, history, site permissions and extensions will be deleted."),
                                                   confirmTitle: "Delete profile", identifier: "profiles.confirmDelete") { [browser, profileID, navigate] in
            await browser.removeProfile(profileID)
            if !browser.profiles.contains(where: { $0.id == profileID }) { navigate(.section(.profiles)) }
        }))
    }

    /// Why deletion is unavailable, or what it erases.
    private func removalNote(hasSpaces: Bool) -> LocalizedStringKey {
        if hasSpaces { "Reassign or delete this profile’s spaces first." }
        else if browser.profiles.count <= 1 { "Keep at least one profile." }
        else { "Cookies, history, site permissions and extensions will be deleted." }
    }
}
