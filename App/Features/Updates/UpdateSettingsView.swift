import BrowserCore
import SwiftUI

struct UpdateSettingsView: View {
    let browser: BrowserModel
    private var updater: AppUpdater { browser.updater }

    var body: some View {
        Form {
            Section {
                LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "")
            }
            Section {
                switch updater.configuration {
                case .disabled:
                    Text("Updates are disabled in development and test builds.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("updates.disabled")
                case .invalid:
                    Text("This copy of Aero is not configured for updates. Download a new copy from getaero.app.")
                case .enabled:
                    if let error = updater.startupError {
                        Text(verbatim: error).foregroundStyle(.secondary)
                    } else {
                        Toggle("Check for updates automatically", isOn: Binding(get: { updater.automaticallyChecks }, set: updater.setAutomaticChecks))
                            .accessibilityIdentifier("updates.automaticChecks")
                        Toggle("Download and install updates automatically", isOn: Binding(get: { updater.automaticallyDownloads }, set: updater.setAutomaticDownloads))
                            .disabled(!updater.automaticallyChecks)
                            .accessibilityIdentifier("updates.automaticDownloads")
                        Text("Updates install when you quit Aero. You can also choose to restart from the update window. Save your work on websites before restarting.")
                            .foregroundStyle(.secondary)
                        if let lastCheck = updater.lastCheck {
                            LabeledContent("Last checked") { Text(lastCheck, format: .dateTime.day().month().hour().minute()) }
                        }
                    }
                }
                Button(BrowserCommand.checkForUpdates.title) { browser.perform(.checkForUpdates) }
                    .disabled(!browser.isEnabled(.checkForUpdates))
                    .accessibilityIdentifier("updates.check")
            } header: {
                Text("Software Updates")
            }
        }
    }
}
