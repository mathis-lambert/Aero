import AppKit
import BrowserCore
import BrowserStorage
import SwiftUI
import UniformTypeIdentifiers

private let maximumCSVBytes = 16 * 1024 * 1024

/// Import sources are visible choices on a dedicated page, scoped to the selected Aero profile.
struct PasswordImportSettingsView: View {
    private enum CSVFileError: Error { case tooLarge, invalidText }

    let browser: BrowserModel
    let profileID: UUID
    let navigate: (SettingsRoute) -> Void
    @State private var sources: [ChromiumProfile] = []
    @State private var importing = false
    @State private var message: String?
    @State private var isError = false
    @Environment(\.palette) private var palette

    var body: some View {
        Form {
            if let profile = browser.profiles.first(where: { $0.id == profileID }) {
                Section {
                    Label { Text("Import into \(profile.name)") } icon: { ProfileMonogram(name: profile.name, size: BrowserDesign.identityHeight) }
                } footer: {
                    Text("Existing passwords are kept when an import has a different password for the same account.")
                }
                Section {
                    if sources.isEmpty {
                        Text("No Chrome, Arc, Dia, Brave, Edge or Vivaldi profile found").foregroundStyle(.secondary)
                    }
                    ForEach(sources) { source in
                        SettingsRow(title: source.browser.name, open: { run { await browser.importPasswords(from: source, into: $0) } }) {
                            Image(systemName: "network")
                        } subtitle: {
                            Text(verbatim: source.name)
                        } trailing: { EmptyView() }
                        .disabled(importing)
                        .accessibilityIdentifier("passwords.importBrowser")
                    }
                } header: {
                    Text("From a browser")
                } footer: {
                    Text("Safari’s passwords are in the Passwords app and cannot be imported here.")
                }
                Section {
                    Button { importCSV() } label: { Label("Choose CSV file…", systemImage: "doc.text") }
                        .disabled(importing)
                        .accessibilityIdentifier("passwords.importCSV")
                } header: {
                    Text("From a CSV file")
                } footer: {
                    Text("Choose a passwords file exported from a browser or password manager.")
                }
                if importing || message != nil {
                    Section {
                        if importing { ProgressView("Importing…") }
                        if let message {
                            Text(message)
                                .foregroundStyle(isError ? palette.miss : .secondary)
                                .accessibilityIdentifier("passwords.message")
                            Button("Done") { navigate(.passwordProfile(profileID)) }
                        }
                    }
                }
            }
        }
        .task {
            let folder = browser.importSourceRoots.applicationSupport
            let found = await Task.detached(priority: .utility) { ChromiumLogins.installedProfiles(in: folder) }.value
            if !Task.isCancelled { sources = found }
        }
    }

    private func run(_ importer: @escaping (UUID) async -> PasswordImportResult) {
        importing = true
        message = nil
        Task {
            let result = await importer(profileID)
            importing = false
            isError = result.failure != nil
            message = result.failure ?? String(localized: "Added: \(result.added) · Already saved: \(result.present) · Skipped: \(result.skipped)")
        }
    }

    private func importCSV() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.message = String(localized: "Choose a passwords file exported from a browser or a password manager.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        run { profileID in
            let parsed: (logins: [LoginRecord], skipped: Int)
            do {
                parsed = try await Task.detached(priority: .userInitiated) {
                    let data = try Data(contentsOf: url, options: .mappedIfSafe)
                    guard data.count <= maximumCSVBytes else { throw CSVFileError.tooLarge }
                    guard let text = String(data: data, encoding: .utf8) else { throw CSVFileError.invalidText }
                    return LoginCSV.parse(text)
                }.value
            } catch CSVFileError.tooLarge {
                return PasswordImportResult(failure: String(localized: "This CSV file is too large to import (16 MB maximum)."))
            } catch {
                return PasswordImportResult(failure: String(localized: "The file could not be read as text."))
            }
            guard !parsed.logins.isEmpty || parsed.skipped > 0 else {
                return PasswordImportResult(failure: String(localized: "This file has no web addresses and passwords."))
            }
            var result = await browser.passwords.save(parsed.logins, into: profileID)
            result.skipped += parsed.skipped
            return result
        }
    }
}
