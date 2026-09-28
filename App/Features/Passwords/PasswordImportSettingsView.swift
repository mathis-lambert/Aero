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
        ScrollView {
            if let profile = browser.profiles.first(where: { $0.id == profileID }) {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 10) {
                        ProfileMonogram(name: profile.name, size: BrowserDesign.identityHeight)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Import into \(profile.name)").font(BrowserDesign.Typography.heading)
                            Text("Existing passwords are kept when an import has a different password for the same account.")
                                .font(BrowserDesign.Typography.caption)
                                .foregroundStyle(palette.secondary)
                        }
                    }

                    FormSection("From a browser") {
                        if sources.isEmpty {
                            Text("No Chrome, Arc, Dia, Brave, Edge or Vivaldi profile found")
                                .font(BrowserDesign.Typography.chrome)
                                .foregroundStyle(palette.secondary)
                        } else {
                            VStack(spacing: 6) {
                                ForEach(sources) { source in
                                    Button { run { await browser.importPasswords(from: source, into: $0) } } label: {
                                        SettingsRow(title: source.browser.name) {
                                            Image(systemName: "network")
                                                .font(BrowserDesign.Typography.chrome)
                                                .frame(width: BrowserDesign.identityHeight, height: BrowserDesign.identityHeight)
                                                .background(palette.fill, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
                                        } subtitle: {
                                            Text(verbatim: source.name)
                                        } trailing: { EmptyView() }
                                    }
                                    .buttonStyle(QuietButtonStyle(radius: BrowserDesign.Radius.card))
                                    .disabled(importing)
                                    .accessibilityIdentifier("passwords.importBrowser")
                                }
                            }
                        }
                    }

                    FormSection("From a CSV file", footer: "Choose a passwords file exported from a browser or password manager.") {
                        Button { importCSV() } label: { Label("Choose CSV file…", systemImage: "doc.text") }
                            .buttonStyle(PanelButtonStyle())
                            .disabled(importing)
                            .accessibilityIdentifier("passwords.importCSV")
                    }

                    if importing { ProgressView("Importing…") }
                    if let message {
                        Text(message)
                            .foregroundStyle(isError ? palette.miss : palette.secondary)
                            .accessibilityIdentifier("passwords.message")
                    }
                    if message != nil {
                        Button("Done") { navigate(.passwordProfile(profileID)) }
                            .buttonStyle(PanelButtonStyle())
                    }
                    Text("Safari’s passwords are in the Passwords app and cannot be imported here.")
                        .font(BrowserDesign.Typography.caption)
                        .foregroundStyle(palette.secondary)
                }
                .frame(maxWidth: BrowserDesign.listWidth, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .task {
            let found = await Task.detached(priority: .utility) { ChromiumLogins.installedProfiles() }.value
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
