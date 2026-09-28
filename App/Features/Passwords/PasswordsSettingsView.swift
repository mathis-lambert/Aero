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
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Passwords are saved separately in each profile’s Mac keychain items.")
                        .font(BrowserDesign.Typography.chrome)
                        .foregroundStyle(palette.secondary)
                    VStack(spacing: 6) {
                        ForEach(browser.profiles) { profile in
                            Button { navigate(.passwordProfile(profile.id)) } label: {
                                SettingsRow(title: profile.name) {
                                    ProfileMonogram(name: profile.name)
                                } subtitle: {
                                    if let count = counts[profile.id] { Text("\(count) saved passwords") }
                                    else { Text("Saved passwords") }
                                } trailing: { EmptyView() }
                            }
                            .buttonStyle(QuietButtonStyle(radius: BrowserDesign.Radius.card))
                            .accessibilityIdentifier("passwords.profile.\(profile.name)")
                        }
                    }
                }

                FormSection("Saving") {
                    Toggle("Offer to save passwords", isOn: preferences.offersToSavePasswords)
                        .accessibilityIdentifier("passwords.offersToSave")
                    Text("After you sign in, Aero asks whether to save the password. Each site can be excluded from its controls.")
                        .font(BrowserDesign.Typography.caption)
                        .foregroundStyle(palette.secondary)
                }

                FormSection("Passkeys") {
                    Text(PasskeyCeremony.isAvailable
                         ? "Sites can use passkeys from iCloud Keychain, a password app, a nearby phone or a security key."
                         : "This build is not signed to use passkeys. Sites offer passwords instead.")
                        .font(BrowserDesign.Typography.chrome)
                        .foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let message { Text(message).foregroundStyle(palette.miss).accessibilityIdentifier("passwords.message") }
            }
            .frame(maxWidth: BrowserDesign.listWidth, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
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
