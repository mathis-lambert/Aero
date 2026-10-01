import AppKit
import BrowserExtensions
import SwiftUI

/// What an extension asks the person to accept: its installation, an update, more permissions, its removal, or a
/// change another extension asks to make to it.
struct ExtensionRequest {
    enum Kind: Equatable {
        case installation, update, permissions, removal
        /// `management`: the extension named `by` asks to change this one.
        case management(ManagementChange, by: String)
    }

    enum ManagementChange { case enabling, disabling, removal }

    let id = UUID()
    let kind: Kind
    let name: String
    let icon: NSImage?
    let permissions: [String]
    let sites: [String]
    /// What it declares that Aero cannot run, shown before it is added.
    let unavailableFeatures: [ExtensionFeature]
    /// Accepting it lets its page replace the New Tab page, as WebKit asks the browser to confirm.
    let replacesNewTab: Bool
    /// Asked from the Settings window, which then shows it.
    let inSettings: Bool
    /// Offered when the extension may fill the profile's passwords in place of Aero.
    let passwordAutoFill: PasswordAutoFillChoice?
    let answer: (Bool) -> Void
}

/// Whether an extension being added fills the profile's passwords; on for a password manager.
@Observable
final class PasswordAutoFillChoice {
    let profileName: String
    var isOn: Bool

    init(profileName: String, isOn: Bool) {
        self.profileName = profileName
        self.isOn = isOn
    }
}

struct ExtensionRequestPrompt: View {
    let browser: BrowserModel
    let request: ExtensionRequest

    private var title: String {
        switch request.kind {
        case .installation: String(localized: "Add “\(request.name)”?")
        case .update: String(localized: "Update “\(request.name)”?")
        case .permissions: String(localized: "“\(request.name)” asks for more access")
        case .removal: String(localized: "“\(request.name)” asks to be removed")
        case .management(.enabling, let requester): String(localized: "“\(requester)” asks to turn on “\(request.name)”")
        case .management(.disabling, let requester): String(localized: "“\(requester)” asks to turn off “\(request.name)”")
        case .management(.removal, let requester): String(localized: "“\(requester)” asks to remove “\(request.name)”")
        }
    }

    private var removesData: Bool {
        switch request.kind {
        case .removal, .management(.removal, _): true
        default: false
        }
    }

    private var confirmTitle: LocalizedStringKey {
        switch request.kind {
        case .installation: "Add"
        case .update: "Update"
        case .permissions: "Allow"
        case .removal, .management(.removal, _): "Remove"
        case .management(.enabling, _): "Turn On"
        case .management(.disabling, _): "Turn Off"
        }
    }

    var body: some View {
        Prompt(title: Text(verbatim: title), icon: request.icon.map(Image.init(nsImage:))) {
            VStack(alignment: .leading, spacing: 8) {
                if !request.sites.isEmpty {
                    Label(ExtensionSiteWarning.warning(for: request.sites), systemImage: "globe")
                }
                ForEach(ExtensionPermissionWarning.warnings(for: request.permissions), id: \.self) { warning in
                    Label(warning, systemImage: "checkmark.shield")
                }
                if request.replacesNewTab {
                    Label("Replace the New Tab page", systemImage: "plus.square.on.square")
                }
                if removesData {
                    Text("Its data in this profile will be deleted.").foregroundStyle(.secondary)
                }
                if let autoFill = request.passwordAutoFill {
                    Toggle(String(localized: "Fill passwords in “\(autoFill.profileName)” with this extension"), isOn: Bindable(autoFill).isOn)
                        .accessibilityIdentifier("extensionRequest.autofill")
                }
                if !request.unavailableFeatures.isEmpty {
                    Label(String(localized: "Not available in Aero: \(request.unavailableFeatures.map(\.title).formatted(.list(type: .and)))"),
                          systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("extensionRequest.unavailable")
                }
            }
        } actions: {
            PromptCancelButton { browser.answer(request, accepted: false) }
                .accessibilityIdentifier("extensionRequest.cancel")
            PromptConfirmButton(title: confirmTitle) { browser.answer(request, accepted: true) }
                .accessibilityIdentifier("extensionRequest.accept")
        }
        .accessibilityIdentifier("extensionRequest")
    }
}
