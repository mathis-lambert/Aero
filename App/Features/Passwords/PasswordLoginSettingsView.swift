import BrowserCore
import SwiftUI

/// A saved login gets its own Settings page, so editing never expands inside the profile list.
struct PasswordLoginSettingsView: View {
    let browser: BrowserModel
    let login: SavedLogin
    let replaceRoute: (SettingsRoute) -> Void
    let didDelete: (UUID) -> Void
    @State private var draft: LoginDraft?
    @State private var deleting = false
    @State private var saving = false
    @State private var message: String?
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 10) {
                    Image(systemName: "globe")
                        .font(BrowserDesign.Typography.heading)
                        .frame(width: BrowserDesign.identityHeight, height: BrowserDesign.identityHeight)
                        .background(palette.fill, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: login.origin.host).font(BrowserDesign.Typography.heading)
                        Text(verbatim: login.origin.rawValue)
                            .font(BrowserDesign.Typography.caption)
                            .foregroundStyle(palette.secondary)
                            .lineLimit(2)
                    }
                }

                FormSection("Account") {
                    if draft != nil {
                        TextField("Username", text: Binding(
                            get: { draft?.username ?? "" },
                            set: { draft?.username = $0 }
                        ))
                        .accessibilityIdentifier("passwords.edit.username")
                    } else {
                        Text(verbatim: login.username.isEmpty ? String(localized: "No username") : login.username)
                            .font(BrowserDesign.Typography.chrome)
                    }
                }

                FormSection("Password") {
                    if draft != nil {
                        TextField("Password", text: Binding(
                            get: { draft?.password ?? "" },
                            set: { draft?.password = $0 }
                        ))
                        .font(.system(.body, design: .monospaced))
                        .accessibilityIdentifier("passwords.edit.password")
                        HStack {
                            Button("Copy password") { if let draft { copy(draft.password) } }
                            Spacer()
                            Button("Cancel") { draft = nil }
                            Button("Save") { if let draft { Task { await save(draft) } } }
                                .buttonStyle(.borderedProminent)
                                .disabled(draft?.password.isEmpty != false || saving)
                                .accessibilityIdentifier("passwords.edit.save")
                        }
                    } else {
                        HStack {
                            Text("••••••••").font(.system(.body, design: .monospaced))
                            Spacer()
                            Button("Show password…") { Task { await reveal() } }
                                .accessibilityIdentifier("passwords.reveal")
                        }
                    }
                }

                Hairline()
                VStack(alignment: .leading, spacing: 8) {
                    Button { deleting = true } label: { Label("Delete password…", systemImage: "trash") }
                        .buttonStyle(PanelButtonStyle())
                        .accessibilityIdentifier("passwords.delete")
                    Text("This removes the login from this profile’s Mac keychain items.")
                        .font(BrowserDesign.Typography.caption)
                        .foregroundStyle(palette.secondary)
                }

                if let message { Text(message).foregroundStyle(palette.secondary).accessibilityIdentifier("passwords.message") }
            }
            .frame(width: BrowserDesign.formWidth, alignment: .leading)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog("Delete this password?", isPresented: $deleting) {
            Button("Delete", role: .destructive) { Task { await delete() } }
        } message: {
            Text("The password for \(login.username.isEmpty ? login.origin.host : login.username) on \(login.origin.host) is removed from your keychain.")
        }
        .onDisappear { draft = nil }
    }

    private func reveal() async {
        let passwords = browser.passwords
        guard await passwords.authorize(reason: String(localized: "show a saved password")) else { return }
        do {
            let password = try await passwords.store.password(for: login)
            guard !Task.isCancelled else { return }
            draft = LoginDraft(username: login.username, password: password)
        } catch { message = Passwords.message(for: error) }
    }

    private func save(_ change: LoginDraft) async {
        saving = true
        defer { saving = false }
        do {
            let saved = try await browser.passwords.store.update(login, username: change.username, password: change.password)
            guard !Task.isCancelled else { return }
            draft = nil
            replaceRoute(.passwordLogin(saved))
        } catch { message = Passwords.message(for: error) }
    }

    private func delete() async {
        do {
            try await browser.passwords.store.delete(login)
            guard !Task.isCancelled else { return }
            draft = nil
            didDelete(login.profileID)
        } catch { message = Passwords.message(for: error) }
    }

    private func copy(_ password: String) {
        browser.passwords.copyToPasteboard(password)
        message = String(localized: "Password copied. It is removed from the clipboard in a minute.")
    }
}

private struct LoginDraft {
    var username: String
    var password: String
}
