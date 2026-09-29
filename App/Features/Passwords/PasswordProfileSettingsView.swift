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
        ScrollView {
            if let profile = browser.profiles.first(where: { $0.id == profileID }) {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 10) {
                        ProfileMonogram(name: profile.name, size: BrowserDesign.identityHeight)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(verbatim: profile.name).font(BrowserDesign.Typography.heading)
                            Text("\(logins.count) saved passwords")
                                .font(BrowserDesign.Typography.caption)
                                .foregroundStyle(palette.secondary)
                        }
                    }

                    FormSection("Saved passwords") {
                        TextField("Search passwords", text: $query)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("passwords.search")
                        if !loaded {
                            ProgressView()
                        } else if shown.isEmpty && !loadFailed {
                            Text(logins.isEmpty ? "No saved passwords in this profile." : "No passwords match.")
                                .font(BrowserDesign.Typography.chrome)
                                .foregroundStyle(palette.secondary)
                                .accessibilityIdentifier("passwords.empty")
                        } else {
                            LazyVStack(spacing: 6) {
                                ForEach(shown) { login in
                                    Button { navigate(.passwordLogin(login)) } label: {
                                        SettingsRow(title: login.origin.host) {
                                            let site = URL(string: login.origin.rawValue)
                                            FaviconView(cache: browser.favicons, key: site.flatMap { FaviconKey(profileID: profileID, url: $0) },
                                                        size: BrowserDesign.tabIconSize, fetchingMissing: site) {
                                                Image(systemName: "globe").font(BrowserDesign.Typography.chrome)
                                            }
                                            .frame(width: BrowserDesign.identityHeight, height: BrowserDesign.identityHeight)
                                            .background(palette.fill, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
                                        } subtitle: {
                                            Text(verbatim: login.username.isEmpty ? String(localized: "No username") : login.username)
                                        } trailing: { EmptyView() }
                                    }
                                    .buttonStyle(QuietButtonStyle(radius: BrowserDesign.Radius.card))
                                    .accessibilityIdentifier("passwords.row")
                                    .accessibilityLabel(Text(verbatim: "\(login.origin.host), \(login.username)"))
                                }
                            }
                        }
                    } accessory: {
                        SectionActionButton("Import passwords…", symbol: "square.and.arrow.down") {
                            navigate(.passwordImport(profileID))
                        }
                        .accessibilityIdentifier("passwords.import")
                    }

                    Hairline()
                    VStack(alignment: .leading, spacing: 8) {
                        Button { Task { await export() } } label: { Label("Export passwords…", systemImage: "square.and.arrow.up") }
                            .buttonStyle(PanelButtonStyle())
                            .disabled(logins.isEmpty)
                            .accessibilityIdentifier("passwords.export")
                        Text("Export creates an unencrypted CSV file. Anyone who can open it can read the passwords.")
                            .font(BrowserDesign.Typography.caption)
                            .foregroundStyle(palette.secondary)
                    }

                    if let message { Text(message).foregroundStyle(palette.miss).accessibilityIdentifier("passwords.message") }
                }
                .frame(maxWidth: BrowserDesign.listWidth, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
        }
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
