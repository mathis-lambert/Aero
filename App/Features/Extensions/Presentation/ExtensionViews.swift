import AppKit
import BrowserCore
import BrowserExtensions
import SwiftUI

enum ExtensionAnchor {
    /// Where popups of extensions without a button on screen hang from.
    static let controlCenter = "aero.controlCenter"
}

/// The selected tab's extension action and badge.
struct ExtensionButton: View {
    private static let iconSize: CGFloat = 16

    let browser: BrowserModel
    let extensions: ProfileExtensions
    let record: InstalledExtension
    let size: CGFloat
    /// Registered as its popup's anchor; buttons that go away with their popover leave it to the control center's.
    var anchorsPopup = false

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
        .tooltip(action.map(\.label).flatMap { $0.isEmpty ? nil : $0 } ?? name)
        .contextMenu { ExtensionMenu(browser: browser, extensions: extensions, record: record) }
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityValue(Text(verbatim: action?.badgeText ?? ""))
        .accessibilityIdentifier("extension.button")
    }
}

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

/// The extension's own items for its button, then Aero's.
struct ExtensionMenu: View {
    let browser: BrowserModel
    let extensions: ProfileExtensions
    let record: InstalledExtension

    var body: some View {
        if let profileID = browser.profile?.id {
            let items = extensions.action(for: record.id)?.menuItems ?? []
            if !items.isEmpty {
                NativeMenuItems(items: items)
                Divider()
            }
            Button(record.isPinned ? "Unpin Extension" : "Pin Extension", systemImage: record.isPinned ? "pin.slash" : "pin") {
                Task { await browser.setPinned(!record.isPinned, record, inProfile: profileID) }
            }
            if let options = extensions.contexts[record.id]?.optionsPageURL {
                Button("Open Extension Options", systemImage: "gearshape") { _ = browser.openTab(options, inProfile: profileID, selected: true) }
            }
            Divider()
            Button("Extension Settings…", systemImage: "puzzlepiece.extension") { browser.showSettings(.extension(profileID: profileID, extensionID: record.id)) }
            Button("Manage Extensions…", systemImage: "puzzlepiece") { browser.showSettings(.section(.extensions)) }
            Divider()
            Button("Remove Extension", systemImage: "trash", role: .destructive) { Task { await browser.removeExtension(record, inProfile: profileID) } }
        }
    }
}

/// Menu items an extension made with WebKit, as SwiftUI menu entries that run them.
struct NativeMenuItems: View {
    let items: [NSMenuItem]

    var body: some View {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
            if item.isSeparatorItem { Divider() }
            else if let submenu = item.submenu {
                Menu(item.title) { NativeMenuItems(items: submenu.items) }
            } else {
                Button(item.title) {
                    if let action = item.action { NSApp.sendAction(action, to: item.target, from: item) }
                }
                .disabled(!item.isEnabled)
            }
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
