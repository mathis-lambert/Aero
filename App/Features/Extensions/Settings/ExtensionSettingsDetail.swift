import AppKit
import BrowserCore
import BrowserExtensions
import SwiftUI
import WebKit

struct ExtensionSettingsDetail: View {
    private static let iconSize = BrowserDesign.identityHeight

    let browser: BrowserModel
    let profileID: UUID
    let extensionID: String
    @State private var confirmsRemoval = false
    @State private var recordingCommand: String?
    @Environment(\.palette) private var palette

    private var record: InstalledExtension? { browser.installedExtension(extensionID, inProfile: profileID) }
    private var owner: ProfileExtensions? { browser.extensions.extensionsIfMade(for: profileID) }
    private var context: WKWebExtensionContext? { owner?.contexts[extensionID] }

    var body: some View {
        ScrollView {
            if let record {
                VStack(alignment: .leading, spacing: 28) {
                    header(record)
                    status(record)
                    desktopApp
                    unavailable
                    access(record)
                    shortcuts
                    options(record)
                    Hairline()
                    Button { confirmsRemoval = true } label: { Label("Remove extension…", systemImage: "trash") }
                        .buttonStyle(PanelButtonStyle())
                        .accessibilityIdentifier("extensions.remove")
                }
                .frame(width: BrowserDesign.formWidth, alignment: .leading)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity)
                .disabled(browser.extensionOperationInProgress(extensionID, profileID: profileID) || !browser.extensionsReady)
            }
        }
        .confirmationDialog("Remove this extension and its data?", isPresented: $confirmsRemoval) {
            Button("Remove extension", role: .destructive) {
                guard let record else { return }
                Task { await browser.removeExtension(record, inProfile: profileID) }
            }
        }
        .accessibilityIdentifier("extensions.detail")
    }

    // MARK: - Sections

    private func header(_ record: InstalledExtension) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ExtensionIcon(image: context?.webExtension.icon(for: CGSize(width: Self.iconSize, height: Self.iconSize)), size: Self.iconSize)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: context?.webExtension.displayName ?? record.id).font(BrowserDesign.Typography.heading)
                Text(verbatim: sourceLine(record)).font(BrowserDesign.Typography.caption).foregroundStyle(palette.secondary)
                if let description = context?.webExtension.displayDescription, !description.isEmpty {
                    Text(verbatim: description)
                        .font(BrowserDesign.Typography.caption)
                        .foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func sourceLine(_ record: InstalledExtension) -> String {
        switch record.source {
        case .webStore: String(localized: "Version \(record.version) · Chrome Web Store")
        case .folder(let folder): String(localized: "Version \(record.version) · \(folder.lastPathComponent) folder")
        }
    }

    private func status(_ record: InstalledExtension) -> some View {
        FormSection("Status") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Enabled", isOn: Binding(get: { record.isEnabled },
                                                  set: { enabled in Task { await browser.setEnabled(enabled, record, inProfile: profileID) } }))
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("extensions.enabled")
                if record.isRemoving {
                    Button("Retry removal") { Task { await browser.removeExtension(record, inProfile: profileID) } }.buttonStyle(PanelButtonStyle())
                }
                if let version = record.pendingVersion {
                    HStack {
                        Text("Version \(version) asks for more access.").font(BrowserDesign.Typography.chrome)
                        Spacer()
                        Button("Review update") { Task { await browser.installFromWebStore(record.id, inProfile: profileID, inSettings: true) } }
                            .buttonStyle(PanelButtonStyle(prominent: true))
                    }
                }
                if record.isEnabled, let status = owner?.status(of: record.id) {
                    switch status.state {
                    case .running:
                        Label("Running", systemImage: "checkmark.circle").font(BrowserDesign.Typography.chrome).foregroundStyle(palette.secondary)
                    case .failed(let reason):
                        VStack(alignment: .leading, spacing: 6) {
                            Label("Could not start", systemImage: "exclamationmark.triangle.fill")
                                .font(BrowserDesign.Typography.chrome)
                                .foregroundStyle(palette.miss)
                            if !reason.isEmpty { errorText(reason) }
                            Button("Try again") { Task { await browser.restartExtension(record, inProfile: profileID) } }
                                .buttonStyle(PanelButtonStyle())
                                .accessibilityIdentifier("extensions.restart")
                        }
                    }
                    if !status.errors.isEmpty, case .running = status.state {
                        DisclosureGroup("Reported errors (\(status.errors.count))") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(Array(status.errors.enumerated()), id: \.offset) { errorText($0.element) }
                            }
                            .padding(.top, 4)
                        }
                        .font(BrowserDesign.Typography.caption)
                    }
                }
            }
        }
    }

    private func errorText(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(palette.secondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Shown for the password managers Aero knows, and for any extension that tried to reach an app.
    @ViewBuilder private var desktopApp: some View {
        let known = KnownExtensions.desktopApp(of: extensionID)
        let link = owner?.desktopApps[extensionID]
        if known != nil || link != nil {
            let name = known?.name ?? link?.application.map { FileManager.default.displayName(atPath: $0.path).replacing(/\.app$/, with: "") }
                ?? link?.hostName ?? ""
            FormSection("Desktop app") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        if let application = link?.application {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: application.path)).resizable().frame(width: 20, height: 20).accessibilityHidden(true)
                        }
                        Text(verbatim: link?.summary(appName: name) ?? String(localized: "Not connected to \(name) yet"))
                            .font(BrowserDesign.Typography.chrome)
                            .foregroundStyle(link?.isConnected == true ? palette.ink : palette.secondary)
                            .accessibilityIdentifier("extensions.desktopApp")
                        Spacer(minLength: 8)
                        if let application = link?.application {
                            Button("Open \(name)") { NSWorkspace.shared.openApplication(at: application, configuration: NSWorkspace.OpenConfiguration()) }
                                .buttonStyle(PanelButtonStyle())
                        }
                    }
                    if let known {
                        Text(verbatim: known.connection)
                            .font(BrowserDesign.Typography.caption)
                            .foregroundStyle(palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder private var unavailable: some View {
        let features = owner?.status(of: extensionID)?.unavailableFeatures ?? []
        if !features.isEmpty {
            FormSection("Not available in Aero") {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(features, id: \.self) { feature in
                        Label(feature.title, systemImage: "minus.circle").font(BrowserDesign.Typography.chrome)
                    }
                }
                .accessibilityIdentifier("extensions.unavailable")
            }
        }
    }

    private func access(_ record: InstalledExtension) -> some View {
        let warnings = ExtensionPermissionWarning.warnings(for: record.grantedPermissions)
        return FormSection("Access") {
            VStack(alignment: .leading, spacing: 4) {
                Label(ExtensionSiteWarning.warning(for: record.grantedSites), systemImage: "globe")
                    .font(BrowserDesign.Typography.chrome)
                ForEach(warnings, id: \.self) { Label($0, systemImage: "checkmark.shield").font(BrowserDesign.Typography.chrome) }
            }
        }
    }

    @ViewBuilder private var shortcuts: some View {
        let commands = owner?.commands(of: extensionID) ?? []
        if !commands.isEmpty {
            FormSection("Keyboard shortcuts") {
                VStack(spacing: 6) {
                    ForEach(commands, id: \.id) { command in
                        ExtensionShortcutRow(browser: browser, profileID: profileID, extensionID: extensionID, command: command,
                                             recording: Binding(get: { recordingCommand == command.id },
                                                                set: { recordingCommand = $0 ? command.id : nil }))
                    }
                }
            }
        }
    }

    private func options(_ record: InstalledExtension) -> some View {
        FormSection("Options") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Show in the address bar", isOn: Binding(get: { record.isPinned },
                                                                set: { pinned in Task { await browser.setPinned(pinned, record, inProfile: profileID) } }))
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("extensions.pin")
                HStack(spacing: 8) {
                    if let url = context?.optionsPageURL {
                        Button("Open extension options") {
                            _ = browser.openTab(url, inProfile: profileID, selected: true)
                            browser.showMainWindow()
                        }
                        .buttonStyle(PanelButtonStyle())
                    }
                    if case .folder = record.source {
                        Button { Task { await browser.reloadExtension(record, inProfile: profileID) } } label: {
                            Label("Reload from folder", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(PanelButtonStyle())
                        .accessibilityIdentifier("extensions.reload")
                    }
                }
            }
        }
    }
}

private struct ExtensionShortcutRow: View {
    let browser: BrowserModel
    let profileID: UUID
    let extensionID: String
    let command: WKWebExtension.Command
    @Binding var recording: Bool
    @State private var candidate: ShortcutBinding?
    @Environment(\.palette) private var palette

    /// WebKit names the action command after the extension rather than the action.
    private var title: String {
        command.id == "_execute_action" || command.title.isEmpty ? String(localized: "Open the extension") : command.title
    }

    private var taken: String? { candidate.flatMap { browser.shortcuts.owner(of: $0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: title).font(BrowserDesign.Typography.chrome).lineLimit(2)
                Spacer(minLength: 8)
                if recording {
                    ShortcutRecorder { event in
                        if event.keyCode == 53 { recording = false; return }
                        if let binding = ShortcutBinding(event: event), binding.isValid { candidate = binding }
                    }
                    .frame(width: 120, height: 28)
                    .overlay {
                        Group {
                            if let candidate { Keycaps(candidate.shortcut) } else { Text("Press shortcut").foregroundStyle(.secondary) }
                        }
                        .allowsHitTesting(false)
                    }
                    .background(palette.fill, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
                    .accessibilityLabel("Record shortcut")
                    Button("Save") {
                        if let candidate { save(.binding(candidate)) }
                    }
                    .disabled(candidate == nil || taken != nil)
                } else {
                    Button {
                        candidate = nil
                        recording = true
                    } label: {
                        Group {
                            if let shortcut = ShortcutBinding(command: command)?.shortcut { Keycaps(shortcut) } else { Text("None") }
                        }
                        .frame(minWidth: 60)
                    }
                    .buttonStyle(PanelButtonStyle())
                    .help("Record shortcut")
                    Menu {
                        Button("Turn off shortcut") { save(.none) }
                        Button("Restore default shortcut") { save(.default) }
                    } label: { Image(systemName: "ellipsis.circle") }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .fixedSize()
                        .accessibilityLabel("Shortcut settings")
                }
            }
            if let taken { Text("Already used by \(taken).").font(BrowserDesign.Typography.caption).foregroundStyle(palette.miss) }
            else if !recording, let binding = ShortcutBinding(command: command), let owner = browser.shortcuts.owner(of: binding) {
                Text("Unavailable: \(owner) uses this shortcut.").font(BrowserDesign.Typography.caption).foregroundStyle(palette.secondary)
            }
        }
    }

    private func save(_ choice: ExtensionShortcutChoice) {
        browser.shortcuts.setExtensionShortcut(choice, command: command.id, of: extensionID)
        recording = false
        candidate = nil
        guard let owner = browser.extensions.extensionsIfMade(for: profileID) else { return }
        if choice == .default { owner.restoreShortcut(forCommand: command.id, of: extensionID) }
        else { browser.applyExtensionShortcuts(extensionID, in: owner) }
    }
}
