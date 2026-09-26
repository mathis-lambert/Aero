import AppKit
import BrowserCore
import SwiftUI
import WebKit

/// Settings › Extensions: the selected profile's extensions, and loading one from a folder.
struct ExtensionsSettingsView: View {
    private static let iconSize: CGFloat = 28

    let browser: BrowserModel

    var body: some View {
        if let profileID = browser.window.selectedProfileID {
            let extensions = browser.pages.extensionsIfMade(for: profileID)
            let installed = browser.installedExtensions(inProfile: profileID)
            Form {
                Section {
                    if installed.isEmpty {
                        Text("No extensions in this profile. Add them from the Chrome Web Store, through the control center of an extension's page.")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("extensions.empty")
                    }
                    ForEach(installed) { record in row(record, webExtension: extensions?.contexts[record.id]?.webExtension, profileID: profileID) }
                } footer: {
                    HStack {
                        Spacer()
                        Button("Add from folder…", action: chooseFolder)
                            .accessibilityIdentifier("extensions.addFromFolder")
                    }
                }
            }
        }
    }

    private func row(_ record: InstalledExtension, webExtension: WKWebExtension?, profileID: UUID) -> some View {
        HStack(spacing: 12) {
            ExtensionIcon(image: webExtension?.icon(for: CGSize(width: Self.iconSize, height: Self.iconSize)), size: Self.iconSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: webExtension?.displayName ?? record.id).lineLimit(1)
                Text(verbatim: record.version).font(BrowserDesign.Typography.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if record.pendingVersion != nil {
                Button("Review update") { Task { await browser.installFromWebStore(record.id, inSettings: true) } }.buttonStyle(PanelButtonStyle(prominent: true))
            }
            if case .folder = record.source {
                IconButton(symbol: "arrow.clockwise", label: "Reload") { Task { await browser.reloadExtension(record, inProfile: profileID) } }
            }
            IconButton(symbol: record.isPinned ? "pin.fill" : "pin", label: record.isPinned ? "Unpin" : "Pin") {
                browser.setPinned(!record.isPinned, record, inProfile: profileID)
            }
            .accessibilityIdentifier("extensions.pin")
            IconButton(symbol: "trash", label: "Remove") { Task { await browser.removeExtension(record, inProfile: profileID) } }
                .accessibilityIdentifier("extensions.remove")
            Toggle("Enabled", isOn: Binding(get: { record.isEnabled }, set: { enabled in Task { await browser.setEnabled(enabled, record, inProfile: profileID) } }))
                .toggleStyle(.switch)
                .labelsHidden()
                .accessibilityIdentifier("extensions.enabled")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("extensions.row")
    }

    /// A sheet on the Settings window, where the review that follows shows too.
    private func chooseFolder() {
        guard let window = NSApp.keyWindow else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = String(localized: "Choose the folder that holds the extension's manifest.json.")
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let folder = panel.url else { return }
            Task { await browser.installFromFolder(folder) }
        }
    }
}
