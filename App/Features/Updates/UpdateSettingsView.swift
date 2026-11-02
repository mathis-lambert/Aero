import AppKit
import BrowserCore
import SwiftUI

/// Settings › Software Updates (docs/UPDATES.md): the app, its version and what the updater is doing, with the one
/// action that fits; the channel updates come from; and the automatic checks and downloads.
struct UpdateSettingsView: View {
    let browser: BrowserModel
    private var updater: AppUpdater { browser.updater }
    @Environment(\.palette) private var palette

    var body: some View {
        Form {
            Section { header }
            Section {
                ForEach(UpdateChannel.allCases) { channel in channelRow(channel) }
            } header: {
                Text("Update channel")
            } footer: {
                Text("Every channel is this same Aero, with your tabs, history and settings. Moving to a steadier channel takes effect with its next release newer than this one.")
                    .foregroundStyle(.secondary)
            }
            if updater.configuration == .enabled, updater.startupError == nil {
                Section {
                    Toggle("Check for updates automatically", isOn: Binding(get: { updater.automaticallyChecks }, set: updater.setAutomaticChecks))
                        .accessibilityIdentifier("updates.automaticChecks")
                    Toggle("Download updates automatically", isOn: Binding(get: { updater.automaticallyDownloads }, set: updater.setAutomaticDownloads))
                        .disabled(!updater.automaticallyChecks)
                        .accessibilityIdentifier("updates.automaticDownloads")
                } header: {
                    Text("Automatic updates")
                } footer: {
                    Text("A downloaded update installs when you quit Aero, or at once from the sidebar. Save your work on websites before restarting.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(verbatim: "Aero").font(.title3.weight(.semibold))
                    Label(updater.channel.title, systemImage: updater.channel.symbol)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(palette.fill, in: Capsule())
                }
                Text("Version \(Self.version) (\(Self.build))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                status
            }
            Spacer(minLength: 12)
            action
        }
        .padding(.vertical, 4)
    }

    /// What the updater is doing, or why it cannot.
    @ViewBuilder private var status: some View {
        Group {
            switch updater.configuration {
            case .disabled:
                Text("Updates are off in development and test builds.").accessibilityIdentifier("updates.disabled")
            case .invalid:
                Text("This copy of Aero is not configured for updates. Download a new copy from getaero.app.")
            case .enabled:
                if let error = updater.startupError {
                    Text(verbatim: error)
                } else {
                    switch updater.status {
                    case .checking:
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Checking for updates…")
                        }
                    case .available(let version): Text("Aero \(version) is available.").foregroundStyle(Color.accentColor)
                    case .ready(let version): Text("Aero \(version) is ready to install.").foregroundStyle(Color.accentColor)
                    case .failed(let message): Text(verbatim: message)
                    case .upToDate, .idle:
                        if let lastCheck = updater.lastCheck {
                            Text("Up to date. Checked \(lastCheck, format: .relative(presentation: .named)).")
                        } else {
                            Text("Not checked yet.")
                        }
                    }
                }
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("updates.status")
    }

    @ViewBuilder private var action: some View {
        switch updater.status {
        case .available:
            Button("Install…") { updater.check() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("updates.install")
        case .ready:
            Button("Restart to Update") { updater.check() }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("updates.restart")
        default:
            Button(BrowserCommand.checkForUpdates.title) { browser.perform(.checkForUpdates) }
                .disabled(!browser.isEnabled(.checkForUpdates))
                .accessibilityIdentifier("updates.check")
        }
    }

    private func channelRow(_ channel: UpdateChannel) -> some View {
        let selected = updater.channel == channel
        return Button { updater.setChannel(channel) } label: {
            HStack(spacing: 12) {
                Image(systemName: channel.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.title).fontWeight(.medium)
                    Text(channel.summary).font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary.opacity(0.5))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(updater.configuration != .enabled)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("updates.channel.\(channel.rawValue)")
    }

    private static let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
    private static let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
}
