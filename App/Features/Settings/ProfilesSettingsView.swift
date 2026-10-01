import BrowserCore
import SwiftUI

struct ProfilesSettingsView: View {
    private static let shownSpaces = 5

    let browser: BrowserModel
    let navigate: (SettingsRoute) -> Void

    var body: some View {
        Form {
            Section {
                ForEach(browser.profiles) { profile in row(profile) }
                if let pending = browser.session.profiles.first(where: \.isRemoving) {
                    Button("Retry profile deletion") { Task { await browser.removeProfile(pending.id) } }
                }
            } footer: {
                Text("Each profile keeps its own cookies, sign-ins, history, site permissions and extensions.")
            }
            Section {
                Button { browser.present(.profile(inSettings: true) { id in navigate(.profile(id)) }) } label: { Label("Create profile…", systemImage: "plus") }
                    .accessibilityIdentifier("profiles.add")
            }
        }
        .disabled(browser.isChangingStructure || !browser.extensionsReady)
    }

    private func row(_ profile: BrowserProfile) -> some View {
        let spaces = browser.session.spaces.filter { $0.profileID == profile.id }
        return SettingsRow(title: profile.name, open: { navigate(.profile(profile.id)) }) {
            ProfileMonogram(name: profile.name)
        } subtitle: {
            Text("\(spaces.count) spaces")
        } trailing: {
            HStack(spacing: 3) {
                ForEach(spaces.prefix(Self.shownSpaces)) { SpaceTile(space: $0, size: 20) }
            }
        }
        .accessibilityIdentifier("profiles.row.\(profile.name)")
    }
}
