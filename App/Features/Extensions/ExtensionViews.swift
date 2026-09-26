import AppKit
import BrowserCore
import BrowserWebKit
import SwiftUI

enum ExtensionAnchor {
    /// Where popups of extensions without a button on screen hang from.
    static let controlCenter = "aero.controlCenter"
}

/// An extension's button: its icon and badge for the selected tab. Clicking runs its action or opens
/// its popup. See docs/EXTENSIONS.md › Button, popup and options.
struct ExtensionButton: View {
    private static let iconSize: CGFloat = 16

    let browser: BrowserModel
    let extensions: ProfileExtensions
    let record: InstalledExtension
    var size: CGFloat = BrowserDesign.navigationButtonSize
    /// Registered as its popup's anchor; buttons that go away with their popover leave it to the control center's.
    var anchorsPopup = false
    @Environment(\.palette) private var palette

    var body: some View {
        let _ = extensions.actionRevision
        let action = extensions.action(for: record.id)
        let name = extensions.contexts[record.id]?.webExtension.displayName ?? record.id
        Button { extensions.performAction(for: record.id) } label: {
            ExtensionIcon(image: action?.icon(for: CGSize(width: Self.iconSize, height: Self.iconSize)), size: Self.iconSize)
            .frame(width: size, height: size)
            .overlay(alignment: .topTrailing) {
                if let badge = action?.badgeText, !badge.isEmpty {
                    Text(verbatim: badge)
                        .font(BrowserDesign.Typography.glyph)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .background(.tint, in: Capsule())
                        .accessibilityHidden(true)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
        }
        .buttonStyle(QuietButtonStyle())
        .background { if anchorsPopup { AnchorView(key: record.id, anchors: browser.window.extensionAnchors) } }
        .tooltip(action?.label.isEmpty == false ? action!.label : name)
        .contextMenu { ExtensionMenu(browser: browser, extensions: extensions, record: record) }
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityValue(Text(verbatim: action?.badgeText ?? ""))
        .accessibilityIdentifier("extension.button")
    }
}

/// An extension's icon, or a generic one while it has none.
struct ExtensionIcon: View {
    let image: NSImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().interpolation(.high) }
            else { Image(systemName: "puzzlepiece.extension").foregroundStyle(.secondary) }
        }
        .frame(width: size, height: size)
    }
}

struct ExtensionMenu: View {
    let browser: BrowserModel
    let extensions: ProfileExtensions
    let record: InstalledExtension

    var body: some View {
        if let profileID = browser.window.selectedProfileID {
            Button(record.isPinned ? "Unpin" : "Pin") { browser.setPinned(!record.isPinned, record, inProfile: profileID) }
            if let options = extensions.contexts[record.id]?.optionsPageURL {
                Button("Options") { _ = browser.openTab(options, inProfile: profileID, selected: true) }
            }
            Divider()
            Button("Remove") { Task { await browser.removeExtension(record, inProfile: profileID) } }
        }
    }
}

/// Registers the view it backs as a popup anchor under `key`.
struct AnchorView: NSViewRepresentable {
    let key: String
    let anchors: NSMapTable<NSString, NSView>

    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) { anchors.setObject(view, forKey: key as NSString) }
}

/// Asks the person to accept an extension's installation, update or new permissions.
struct ExtensionRequestPrompt: View {
    private static let everySite: Set = ["<all_urls>", "*://*/*", "http://*/*", "https://*/*"]

    let browser: BrowserModel
    let request: ExtensionRequest

    private var title: String {
        switch request.kind {
        case .installation: String(localized: "Add “\(request.name)”?")
        case .update: String(localized: "Update “\(request.name)”?")
        case .permissions: String(localized: "“\(request.name)” asks for more access")
        }
    }

    var body: some View {
        Prompt(title: Text(verbatim: title), icon: request.icon.map(Image.init(nsImage:))) {
            VStack(alignment: .leading, spacing: 8) {
                if !request.sites.isEmpty {
                    Label(request.sites.contains(where: Self.everySite.contains)
                          ? String(localized: "Read and change your data on every website")
                          : String(localized: "Read and change your data on \(request.sites.joined(separator: ", "))"),
                          systemImage: "globe")
                }
                if !request.permissions.isEmpty {
                    Label(String(localized: "Uses: \(request.permissions.joined(separator: ", "))"), systemImage: "puzzlepiece.extension")
                        .foregroundStyle(.secondary)
                }
            }
        } actions: {
            PromptCancelButton { browser.answer(request, accepted: false) }
                .accessibilityIdentifier("extensionRequest.cancel")
            PromptConfirmButton(title: request.kind == .permissions ? "Allow" : request.kind == .update ? "Update" : "Add") {
                browser.answer(request, accepted: true)
            }
            .accessibilityIdentifier("extensionRequest.accept")
        }
        .accessibilityIdentifier("extensionRequest")
    }
}
