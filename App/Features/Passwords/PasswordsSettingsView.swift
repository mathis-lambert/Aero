import BrowserWebKit
import SwiftUI

/// Password settings start with the profiles that own the saved logins.
struct PasswordsSettingsView: View {
    let browser: BrowserModel
    let navigate: (SettingsRoute) -> Void
    @State private var counts: [UUID: Int] = [:]
    @State private var message: String?
    @Environment(\.palette) private var palette

    var body: some View {
        let preferences = Bindable(browser.preferences)
        Form {
            Section {
                ForEach(browser.profiles) { profile in
                    SettingsRow(title: profile.name, open: { navigate(.passwordProfile(profile.id)) }) {
                        ProfileMonogram(name: profile.name)
                    } subtitle: {
                        if let count = counts[profile.id] { Text("\(count) saved passwords") }
                        else { Text("Saved passwords") }
                    } trailing: { EmptyView() }
                    .accessibilityIdentifier("passwords.profile.\(profile.name)")
                }
            } footer: {
                Text("Passwords are saved separately in each profile’s Mac keychain items.")
            }
            Section {
                Toggle(isOn: preferences.offersToSavePasswords) {
                    Text("Offer to save passwords")
                    Text("After you sign in, Aero asks whether to save the password. Each site can be excluded from its controls.")
                }
                .accessibilityIdentifier("passwords.offersToSave")
            }
            if let message {
                Section { Text(message).foregroundStyle(palette.miss).accessibilityIdentifier("passwords.message") }
            }
        }
        .task { await loadCounts() }
    }

    private func loadCounts() async {
        for profile in browser.profiles {
            do {
                let count = try await browser.passwords.store.logins(profileID: profile.id).count
                guard !Task.isCancelled else { return }
                counts[profile.id] = count
            } catch {
                guard !Task.isCancelled else { return }
                message = Passwords.message(for: error)
            }
        }
    }
}
