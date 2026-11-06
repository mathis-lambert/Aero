import AppKit
import SwiftUI

struct SystemPasskeysSection: View {
    let access: PasskeyAccess
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Section {
            LabeledContent("System passkeys") {
                status
            }
            if access.isRequesting {
                ProgressView().controlSize(.small)
                    .accessibilityLabel("Requesting passkey access")
            } else if access.state == .notDetermined {
                Button("Allow passkey access") { Task { await access.requestAccess() } }
            } else if access.state == .denied {
                Button("Open Privacy & Security") {
                    // Open the supported preferences pane, rather than relying on an undocumented passkey anchor.
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Text("In Privacy & Security, open Passkeys Access for Web Browsers and allow Aero.")
            }
        } footer: {
            Text("macOS and your credential provider manage passkeys. This permission lets Aero discover available passkeys; websites sign you in using the system window.")
        }
        .task { access.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { access.refresh() }
        }
    }

    @ViewBuilder private var status: some View {
        switch access.state {
        case .authorized: Text("Access allowed")
        case .denied: Text("Access denied")
        case .notDetermined: Text("Access not requested")
        case nil: Text("Requires a signed Aero release")
        @unknown default: Text("Access unavailable")
        }
    }
}
