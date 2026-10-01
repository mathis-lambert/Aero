import AppKit
import BrowserCore
import BrowserExtensions
import SwiftUI

struct ExtensionsSettingsView: View {
    static let iconSize: CGFloat = 28
    static let webStore = URL(string: "https://chromewebstore.google.com")!

    let browser: BrowserModel
    let navigate: (SettingsRoute) -> Void
    @State private var storeLink = ""
    @State private var removal: (record: InstalledExtension, profileID: UUID)?
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            if let profile = browser.profile {
                let installed = browser.session.profiles.first { $0.id == profile.id }?.extensions ?? []
                VStack(alignment: .leading, spacing: 16) {
                    SettingsListIntro(text: "Extensions in the \(profile.name) profile.") {
                        Button { openWebStore() } label: { Label("Chrome Web Store", systemImage: "arrow.up.forward.app") }
                            .accessibilityIdentifier("extensions.webStore")
                    }
                    HStack(spacing: 8) {
                        TextField("Chrome Web Store link or extension ID", text: $storeLink)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { installStoreLink(inProfile: profile.id) }
                            .accessibilityIdentifier("extensions.storeLink")
                        Button("Add") { installStoreLink(inProfile: profile.id) }
                            .buttonStyle(PanelButtonStyle(prominent: true))
                            .disabled(WebStore.extensionID(in: storeLink) == nil || !browser.extensionsReady)
                            .accessibilityIdentifier("extensions.addFromStore")
                    }
                    if installed.isEmpty {
                        Text("No extensions in this profile yet.")
                            .font(BrowserDesign.Typography.chrome)
                            .foregroundStyle(palette.secondary)
                            .accessibilityIdentifier("extensions.empty")
                    }
                    VStack(spacing: 6) {
                        ForEach(installed) { record in row(record, profileID: profile.id) }
                    }
                    HStack {
                        Spacer()
                        Button("Add from folder…", action: chooseFolder)
                            .buttonStyle(PanelButtonStyle())
                            .disabled(!browser.extensionsReady)
                            .help("Load an unpacked extension")
                            .accessibilityIdentifier("extensions.addFromFolder")
                    }
                }
                .frame(maxWidth: BrowserDesign.listWidth)
                .padding(.horizontal, 20)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .confirmationDialog("Remove this extension and its data?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } })) {
            if let removal {
                Button("Remove extension", role: .destructive) {
                    Task { await browser.removeExtension(removal.record, inProfile: removal.profileID) }
                    self.removal = nil
                }
            }
        }
    }

    private func row(_ record: InstalledExtension, profileID: UUID) -> some View {
        let context = browser.extensions.extensionsIfMade(for: profileID)?.contexts[record.id]
        let summary = browser.extensionSummary(record, inProfile: profileID)
        return HStack(spacing: 8) {
            Button { navigate(.extension(profileID: profileID, extensionID: record.id)) } label: {
                SettingsRow(title: context?.webExtension.displayName ?? record.id) {
                    ExtensionIcon(image: context?.webExtension.icon(for: CGSize(width: Self.iconSize, height: Self.iconSize)), size: Self.iconSize)
                } subtitle: {
                    HStack(spacing: 4) {
                        if summary.needsAttention {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(palette.miss).accessibilityHidden(true)
                        }
                        Text(verbatim: summary.text)
                    }
                } trailing: { EmptyView() }
            }
            .buttonStyle(QuietButtonStyle(radius: BrowserDesign.Radius.card))
            .accessibilityIdentifier("extensions.list.details")
            Toggle("Enabled", isOn: Binding(get: { record.isEnabled && !record.isRemoving },
                                               set: { enabled in Task { await browser.setEnabled(enabled, record, inProfile: profileID) } }))
                .labelsHidden().toggleStyle(.switch)
                .accessibilityIdentifier("extensions.list.enabled")
                .disabled(record.isRemoving)
            Menu {
                Button(record.isPinned ? "Unpin Extension" : "Pin Extension", systemImage: record.isPinned ? "pin.slash" : "pin") {
                    Task { await browser.setPinned(!record.isPinned, record, inProfile: profileID) }
                }
                if let options = context?.optionsPageURL {
                    Button("Open Extension Options", systemImage: "gearshape") {
                        _ = browser.openTab(options, inProfile: profileID, selected: true)
                        browser.showMainWindow()
                    }
                }
                if case .folder = record.source {
                    Button("Reload from folder", systemImage: "arrow.clockwise") {
                        Task { await browser.reloadExtension(record, inProfile: profileID) }
                    }
                }
                Button("Extension Settings…", systemImage: "gearshape") { navigate(.extension(profileID: profileID, extensionID: record.id)) }
                Divider()
                Button("Remove extension…", systemImage: "trash", role: .destructive) { removal = (record, profileID) }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("Extension Settings…")
            .accessibilityIdentifier("extensions.list.actions")
            .padding(.trailing, 12)
        }
        .disabled(browser.extensionOperationInProgress(record.id, profileID: profileID) || !browser.extensionsReady)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("extensions.row")
    }

    private func installStoreLink(inProfile profileID: UUID) {
        guard let id = WebStore.extensionID(in: storeLink) else { return }
        storeLink = ""
        Task { await browser.installFromWebStore(id, inProfile: profileID, inSettings: true) }
    }

    private func openWebStore() {
        browser.open(Self.webStore)
        browser.showMainWindow()
    }

    /// A sheet on the Settings window, where the review that follows shows too.
    private func chooseFolder() {
        guard let window = NSApp.keyWindow, let profileID = browser.profile?.id else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = String(localized: "Choose the folder that holds the extension's manifest.json.")
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let folder = panel.url else { return }
            Task { await browser.installFromFolder(folder, inProfile: profileID) }
        }
    }
}

/// One line on an extension's state, the most pressing first.
struct ExtensionSummary {
    let text: String
    let needsAttention: Bool
}

extension BrowserModel {
    func extensionSummary(_ record: InstalledExtension, inProfile profileID: UUID) -> ExtensionSummary {
        let owner = extensions.extensionsIfMade(for: profileID)
        if record.isRemoving { return ExtensionSummary(text: String(localized: "Removal did not finish"), needsAttention: true) }
        if !record.isEnabled { return ExtensionSummary(text: String(localized: "Off"), needsAttention: false) }
        if let version = record.pendingVersion {
            return ExtensionSummary(text: String(localized: "Version \(version) needs review"), needsAttention: true)
        }
        guard let status = owner?.status(of: record.id) else {
            return extensionsReady ? ExtensionSummary(text: String(localized: "Could not be loaded"), needsAttention: true)
                : ExtensionSummary(text: String(localized: "Starting…"), needsAttention: false)
        }
        if case .failed = status.state { return ExtensionSummary(text: String(localized: "Could not start"), needsAttention: true) }
        if let app = KnownExtensions.desktopApp(of: record.id), let link = owner?.desktopApps[record.id], !link.isConnected {
            return ExtensionSummary(text: String(localized: "Not connected to \(app.name)"), needsAttention: true)
        }
        if !status.unavailableFeatures.isEmpty {
            return ExtensionSummary(text: String(localized: "On · Limited features"), needsAttention: false)
        }
        return ExtensionSummary(text: String(localized: "On"), needsAttention: false)
    }
}
