import BrowserCore
import SwiftUI

/// Laid out like the space form: identity first, then what uses it, then deletion.
struct ProfileSettingsDetail: View {
    let browser: BrowserModel
    let profileID: UUID
    let navigate: (SettingsRoute) -> Void
    @State private var confirmsRemoval = false
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            if let profile = browser.profiles.first(where: { $0.id == profileID }) {
                let spaces = browser.session.spaces.filter { $0.profileID == profileID }
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 10) {
                            ProfileMonogram(name: profile.name, size: BrowserDesign.identityHeight)
                            SettingsNameField(name: profile.name, maximumLength: BrowserProfile.maximumNameLength, identifier: "profiles.name") {
                                browser.renameProfile(profileID, to: $0)
                            }
                        }
                        Text("Cookies, sign-ins, history, site permissions and extensions stay in this profile. Its spaces share them.")
                            .font(BrowserDesign.Typography.caption)
                            .foregroundStyle(palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    FormSection("Spaces") {
                        if spaces.isEmpty {
                            Text("No spaces use this profile.")
                                .font(BrowserDesign.Typography.chrome)
                                .foregroundStyle(palette.secondary)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(spaces) { space in
                                    Button { navigate(.space(space.id)) } label: {
                                        SettingsRow(title: space.name) {
                                            SpaceTile(space: space)
                                        } subtitle: {
                                            Text("\(browser.session.tabs.count { $0.spaceID == space.id }) tabs")
                                        } trailing: { EmptyView() }
                                    }
                                    .buttonStyle(QuietButtonStyle(radius: BrowserDesign.Radius.card))
                                }
                            }
                        }
                    } accessory: {
                        SectionActionButton("Manage spaces…", symbol: "square.stack") { navigate(.section(.spaces)) }
                    }
                    Hairline()
                    VStack(alignment: .leading, spacing: 8) {
                        Button { confirmsRemoval = true } label: { Label("Delete profile…", systemImage: "trash") }
                            .buttonStyle(PanelButtonStyle())
                            .disabled(!browser.canRemoveProfile(profileID))
                            .accessibilityIdentifier("profiles.delete")
                        Text(removalNote(hasSpaces: !spaces.isEmpty))
                            .font(BrowserDesign.Typography.caption)
                            .foregroundStyle(palette.secondary)
                    }
                }
                .frame(width: BrowserDesign.formWidth, alignment: .leading)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
            }
        }
        .disabled(browser.isChangingStructure)
        .confirmationDialog("Delete profile and its browsing data?", isPresented: $confirmsRemoval) {
            Button("Delete profile", role: .destructive) {
                Task {
                    await browser.removeProfile(profileID)
                    if !browser.profiles.contains(where: { $0.id == profileID }) { navigate(.section(.profiles)) }
                }
            }
        } message: { Text("Cookies, history, site permissions and extensions will be deleted.") }
    }

    /// Why deletion is unavailable, or what it erases.
    private func removalNote(hasSpaces: Bool) -> LocalizedStringKey {
        if hasSpaces { "Reassign or delete this profile’s spaces first." }
        else if browser.profiles.count <= 1 { "Keep at least one profile." }
        else { "Cookies, history, site permissions and extensions will be deleted." }
    }
}
