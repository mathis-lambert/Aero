import BrowserCore
import SwiftUI

/// A saved login gets its own Settings page, so editing never expands inside the profile list.
struct PasswordLoginSettingsView: View {
    let browser: BrowserModel
    let login: SavedLogin
    let replaceRoute: (SettingsRoute) -> Void
    let didDelete: (UUID) -> Void
    @State private var draft: LoginDraft?
    @State private var saving = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                LabeledContent {
                    Text(verbatim: login.origin.rawValue).lineLimit(2)
                } label: {
                    Label { Text(verbatim: login.origin.host) } icon: { Image(systemName: "globe") }
                }
            }
            Section {
                if draft != nil {
                    TextField("Username", text: Binding(get: { draft?.username ?? "" }, set: { draft?.username = $0 }))
                        .accessibilityIdentifier("passwords.edit.username")
                    TextField("Password", text: Binding(get: { draft?.password ?? "" }, set: { draft?.password = $0 }))
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
                    LabeledContent("Username") {
                        Text(verbatim: login.username.isEmpty ? String(localized: "No username") : login.username)
                    }
                    LabeledContent("Password") {
                        HStack {
                            Text(verbatim: "••••••••").font(.system(.body, design: .monospaced))
                            Button("Show password…") { Task { await reveal() } }
                                .accessibilityIdentifier("passwords.reveal")
                        }
                    }
                }
            }
            Section {
                Button(role: .destructive, action: confirmDeletion) { Label("Delete password…", systemImage: "trash") }
                    .accessibilityIdentifier("passwords.delete")
            } footer: {
                Text("This removes the login from this profile’s Mac keychain items.")
            }
            if let message {
                Section { Text(message).foregroundStyle(.secondary).accessibilityIdentifier("passwords.message") }
            }
        }
        .onDisappear { draft = nil }
    }

    private func confirmDeletion() {
        browser.present(.confirmation(Confirmation(id: "deletePassword", title: Text("Delete this password?"),
                                                   message: Text("The password for \(login.username.isEmpty ? login.origin.host : login.username) on \(login.origin.host) is removed from your keychain."),
                                                   confirmTitle: "Delete", identifier: "passwords.confirmDelete") { await delete() }))
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
