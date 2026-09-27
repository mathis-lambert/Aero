import BrowserCore
import SwiftUI

struct ProfilesSettingsView: View {
    private static let shownSpaces = 5

    let browser: BrowserModel
    let navigate: (SettingsRoute) -> Void
    @State private var creating = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SettingsListIntro(text: "Each profile keeps its own cookies, sign-ins, history, site permissions and extensions.") {
                    Button { creating = true } label: { Label("Create profile…", systemImage: "plus") }
                        .accessibilityIdentifier("profiles.add")
                }
                VStack(spacing: 6) {
                    ForEach(browser.profiles) { profile in row(profile) }
                }
                if let pending = browser.session.profiles.first(where: \.isRemoving) {
                    Button("Retry profile deletion") { Task { await browser.removeProfile(pending.id) } }
                        .buttonStyle(PanelButtonStyle())
                }
            }
            .frame(maxWidth: BrowserDesign.listWidth)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .disabled(browser.isChangingStructure || !browser.extensionsReady)
        .sheet(isPresented: $creating) {
            ProfilePrompt(browser: browser, usesSheetBackground: true, onCreated: { id in creating = false; navigate(.profile(id)) }, onCancel: { creating = false })
        }
    }

    private func row(_ profile: BrowserProfile) -> some View {
        let spaces = browser.session.spaces.filter { $0.profileID == profile.id }
        return Button { navigate(.profile(profile.id)) } label: {
            SettingsRow(title: profile.name) {
                ProfileMonogram(name: profile.name)
            } subtitle: {
                Text("\(spaces.count) spaces")
            } trailing: {
                HStack(spacing: 3) {
                    ForEach(spaces.prefix(Self.shownSpaces)) { SpaceTile(space: $0, size: 20) }
                }
            }
        }
        .buttonStyle(QuietButtonStyle(radius: BrowserDesign.Radius.card))
        .accessibilityIdentifier("profiles.row.\(profile.name)")
    }
}
