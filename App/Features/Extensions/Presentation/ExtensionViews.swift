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
        .overlay { ExtensionMenuHost { ExtensionMenu.make(browser: browser, extensions: extensions, record: record) } }
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

/// The extension's own items for its button, as WebKit made them, then Aero's, in a native menu: WebKit's items keep
/// their state, images, shortcuts and validation.
@MainActor
enum ExtensionMenu {
    static func make(browser: BrowserModel, extensions: ProfileExtensions, record: InstalledExtension) -> NSMenu? {
        guard let profileID = browser.profile?.id else { return nil }
        let menu = NSMenu()
        let items = extensions.action(for: record.id)?.menuItems ?? []
        if !items.isEmpty {
            items.forEach(menu.addItem)
            menu.addItem(.separator())
        }
        menu.addItem(ActionMenuItem(record.isPinned ? String(localized: "Unpin Extension") : String(localized: "Pin Extension"),
                                    symbol: record.isPinned ? "pin.slash" : "pin") {
            Task { await browser.setPinned(!record.isPinned, record, inProfile: profileID) }
        })
        if let options = extensions.contexts[record.id]?.optionsPageURL {
            menu.addItem(ActionMenuItem(String(localized: "Open Extension Options"), symbol: "gearshape") {
                _ = browser.openTab(options, inProfile: profileID, selected: true)
            })
        }
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(String(localized: "Extension Settings…"), symbol: "puzzlepiece.extension") {
            browser.showSettings(.extension(profileID: profileID, extensionID: record.id))
        })
        menu.addItem(ActionMenuItem(String(localized: "Manage Extensions…"), symbol: "puzzlepiece") { browser.showSettings(.section(.extensions)) })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(String(localized: "Remove Extension…"), symbol: "trash") {
            browser.confirmRemoval(of: record, inProfile: profileID, inSettings: false)
        })
        return menu
    }
}

/// A menu item that runs a closure.
@MainActor
final class ActionMenuItem: NSMenuItem {
    private let handler: @MainActor () -> Void

    init(_ title: String, symbol: String, handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("Not decoded") }

    @objc private func run() { handler() }
}

/// Shows a native menu on a secondary click of the view it covers, which takes every other click.
struct ExtensionMenuHost: NSViewRepresentable {
    let menu: @MainActor () -> NSMenu?

    func makeNSView(context: Context) -> HostView { HostView() }
    func updateNSView(_ view: HostView, context: Context) { view.makeMenu = menu }

    final class HostView: NSView {
        var makeMenu: (@MainActor () -> NSMenu?)?

        override func menu(for event: NSEvent) -> NSMenu? { makeMenu?() }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard let event = NSApp.currentEvent else { return nil }
            let secondary = event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            return secondary ? super.hitTest(point) : nil
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
