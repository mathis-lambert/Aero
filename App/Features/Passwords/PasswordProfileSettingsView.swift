import AppKit
import BrowserCore
import BrowserStorage
import SwiftUI
import UniformTypeIdentifiers

/// One profile's saved logins, with transfer actions kept apart from individual accounts.
struct PasswordProfileSettingsView: View {
    let browser: BrowserModel
    let profileID: UUID
    let navigate: (SettingsRoute) -> Void
    @State private var logins: [SavedLogin] = []
    @State private var loaded = false
    @State private var loadFailed = false
    @State private var query = ""
    @State private var message: String?
    @Environment(\.palette) private var palette

    private var shown: [SavedLogin] {
        guard !query.isEmpty else { return logins }
        return logins.filter { $0.origin.host.localizedStandardContains(query) || $0.username.localizedStandardContains(query) }
    }

    var body: some View {
        Form {
            if let profile = browser.profiles.first(where: { $0.id == profileID }) {
                Section {
                    LabeledContent {
                        Text("\(logins.count) saved passwords")
                    } label: {
                        Label {
                            Text(verbatim: profile.name)
                        } icon: {
                            ProfileMonogram(name: profile.name, size: BrowserDesign.identityHeight)
                        }
                    }
                }
                Section {
                    Picker("Fill passwords with", selection: Binding(
                        get: { browser.passwordExtension(inProfile: profileID) },
                        set: { browser.setPasswordExtension($0, inProfile: profileID) })) {
                        Text("Aero").tag(String?.none)
                        ForEach(browser.passwordExtensionCandidates(inProfile: profileID), id: \.id) { candidate in
                            Text(verbatim: candidate.name).tag(Optional(candidate.id))
                        }
                    }
                    .accessibilityIdentifier("passwords.autofill")
                } header: {
                    Text("AutoFill")
                } footer: {
                    Text("An extension chosen here fills and saves this profile’s passwords on websites, and Aero stops offering its own. The passwords saved in Aero stay here.")
                }
                Section {
                    if !loaded {
                        ProgressView()
                    } else if shown.isEmpty && !loadFailed {
                        Text(logins.isEmpty ? "No saved passwords in this profile." : "No passwords match.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("passwords.empty")
                    }
                    ForEach(shown) { login in
                        SettingsRow(title: login.origin.host, open: { navigate(.passwordLogin(login)) }) {
                            let site = URL(string: login.origin.rawValue)
                            FaviconView(cache: browser.favicons, key: site.flatMap { FaviconKey(profileID: profileID, url: $0) },
                                        size: BrowserDesign.tabIconSize, fetchingMissing: site) {
                                Image(systemName: "globe")
                            }
                            .frame(width: BrowserDesign.identityHeight, height: BrowserDesign.identityHeight)
                            .background(palette.fill, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
                        } subtitle: {
                            Text(verbatim: login.username.isEmpty ? String(localized: "No username") : login.username)
                        } trailing: { EmptyView() }
                        .accessibilityIdentifier("passwords.row")
                        .accessibilityLabel(Text(verbatim: "\(login.origin.host), \(login.username)"))
                    }
                } header: {
                    Text("Saved passwords")
                }
                Section {
                    Button { navigate(.passwordImport(profileID)) } label: { Label("Import passwords…", systemImage: "square.and.arrow.down") }
                        .accessibilityIdentifier("passwords.import")
                    Button { Task { await export() } } label: { Label("Export passwords…", systemImage: "square.and.arrow.up") }
                        .disabled(logins.isEmpty)
                        .accessibilityIdentifier("passwords.export")
                } footer: {
                    Text("Export creates an unencrypted CSV file. Anyone who can open it can read the passwords.")
                }
                if let message {
                    Section { Text(message).foregroundStyle(palette.miss).accessibilityIdentifier("passwords.message") }
                }
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: Text("Search passwords"))
        .task { await reload() }
    }

    private func reload() async {
        do {
            let found = try await browser.passwords.store.logins(profileID: profileID).sorted {
                ($0.origin.host, $0.username.lowercased()) < ($1.origin.host, $1.username.lowercased())
            }
            guard !Task.isCancelled else { return }
            logins = found
            loadFailed = false
        } catch {
            guard !Task.isCancelled else { return }
            loadFailed = true
            message = Passwords.message(for: error)
        }
        loaded = true
    }

    private func export() async {
        let passwords = browser.passwords
        guard !logins.isEmpty, await passwords.authorize(reason: String(localized: "export your passwords")) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = String(localized: "Aero Passwords.csv")
        panel.message = String(localized: "The file is not encrypted: anyone who can open it can read your passwords.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            var records: [LoginRecord] = []
            for login in logins {
                records.append(LoginRecord(origin: login.origin, username: login.username,
                                           password: try await passwords.store.password(for: login)))
            }
            let file = FileManager.default
            let temporary = url.deletingLastPathComponent().appendingPathComponent(".aero-passwords-\(UUID().uuidString)")
            guard file.createFile(atPath: temporary.path, contents: Data(LoginCSV.export(records).utf8),
                                  attributes: [.posixPermissions: 0o600]) else {
                message = String(localized: "The file could not be written.")
                return
            }
            defer { try? file.removeItem(at: temporary) }
            if file.fileExists(atPath: url.path) {
                _ = try file.replaceItemAt(url, withItemAt: temporary, backupItemName: nil, options: .usingNewMetadataOnly)
            }
            else { try file.moveItem(at: temporary, to: url) }
            message = String(localized: "Passwords exported: \(records.count)")
        } catch let error as PasswordStoreError {
            message = Passwords.message(for: error)
        } catch {
            message = String(localized: "The file could not be written.")
        }
    }
}
