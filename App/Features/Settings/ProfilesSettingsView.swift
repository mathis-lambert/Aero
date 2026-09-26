import BrowserCore
import SwiftUI

/// Settings › Profiles: every profile, and the chosen one's name, emoji and color, edited in place.
struct ProfilesSettingsView: View {
    let browser: BrowserModel
    @State private var draft = ProfileDraft()

    var body: some View {
        Form {
            Section("Your profiles") {
                ForEach(browser.session.profiles) { profile in
                    Button { draft = ProfileDraft(profile) } label: {
                        HStack(spacing: 10) {
                            ProfileBadge(profile: profile)
                            Text(verbatim: profile.name)
                            Spacer()
                            if profile.id == draft.id { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("profiles.row.\(profile.name)")
                }
                Button("Add profile", systemImage: "plus") { draft = ProfileDraft() }
                    .accessibilityIdentifier("profiles.add")
            }
            Section {
                ProfileFields(draft: $draft)
                HStack {
                    if let id = draft.id, id != browser.window.selectedProfileID {
                        Button("Use profile") { browser.switchProfile(id) }
                            .accessibilityIdentifier("profiles.use")
                    }
                    Spacer()
                    Button(draft.id == nil ? "Create profile" : "Save changes") {
                        // A created profile becomes the selected one, which the form then edits.
                        if draft.save(in: browser), draft.id == nil { draft = ProfileDraft(browser.profile) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!draft.isValid)
                    .accessibilityIdentifier("profiles.save")
                }
            } header: {
                Text(draft.id == nil ? "New profile" : "Profile details")
            } footer: {
                Text("Cookies and website sign-ins stay separate for each profile.")
            }
        }
        .onAppear { draft = ProfileDraft(browser.profile) }
    }
}
