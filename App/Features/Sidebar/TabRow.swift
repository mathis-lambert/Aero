import AppKit
import BrowserCore
import SwiftUI

/// One glass lens shared by the selected row, so selection slides between rows instead of blinking.
struct SelectionHighlight: View {
    static let id = "sidebar.selection"
    let namespace: Namespace.ID

    var body: some View {
        Color.clear
            .browserGlass(.selection, radius: BrowserDesign.Radius.control)
            .matchedGeometryEffect(id: Self.id, in: namespace)
    }
}

/// A favorite or an open tab in the sidebar's list. Closing a favorite only unloads it, hence its
/// minus; a dragged tab shows as a gap where it would land, and a tab picked with ⌘ or ⇧ as selected. A favorite away
/// from its pinned page offers to go back to it; a double click does too.
struct TabRow: View {
    let browser: BrowserModel
    let tab: BrowserTab
    let selected: Bool
    let marked: Bool
    let lifted: Bool
    let selection: Namespace.ID
    let layout: TabDropLayout
    @State private var hovered = false
    @Environment(\.palette) private var palette

    var body: some View {
        let removesFavorite = tab.isFavorite && !browser.isTabOpen(tab)
        HStack(spacing: 4) {
            if browser.window.renaming == .tab(tab.id) {
                label {
                    RenameField(name: tab.displayTitle) { browser.renameTab(tab.id, to: $0) } end: { browser.window.endRenaming(.tab(tab.id)) }
                }
            } else if browser.window.renaming == .pinnedPage(tab.id) {
                label { PinnedPageField(browser: browser, tab: tab) }
            } else {
                Button { browser.click(tab, modifiers: NSEvent.modifierFlags) } label: {
                    label { title }
                }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture(count: 2).onEnded { browser.returnToPinnedPage(tab.id) })
                .tabDraggable(tab, browser: browser)
                .accessibilityAddTraits(selected || marked ? .isSelected : [])
                .accessibilityIdentifier(tab.isFavorite ? "sidebar.favorite" : "sidebar.tab")
                if tab.hasLeftPinnedPage {
                    PinnedPageReturn(browser: browser, tab: tab, style: .inline).transition(.opacity)
                }
            }
            ActivityIndicators(browser: browser, tabID: tab.id)
            Button {
                if removesFavorite { browser.removeFavorite(tab.id) }
                else { browser.closeTab(tab.id) }
            } label: {
                Image(systemName: tab.isFavorite && !removesFavorite ? "minus" : "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.ink)
                    .frame(width: 24, height: 24)
                    .contentShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
            }
            .buttonStyle(QuietButtonStyle())
            .padding(.trailing, 5)
            .opacity(hovered || selected ? 1 : 0)
            .accessibilityLabel(removesFavorite ? Text("Remove from Favorites") : Text("Close tab"))
            .accessibilityIdentifier(removesFavorite ? "sidebar.removeFavorite" : "sidebar.closeTab")
        }
        .opacity(lifted ? 0 : 1)
        .background {
            if lifted { RoundedRectangle(cornerRadius: BrowserDesign.Radius.control).fill(palette.fill) }
            else if selected { SelectionHighlight(namespace: selection) }
            else if marked { Color.clear.browserGlass(.hover, radius: BrowserDesign.Radius.control) }
            else { RoundedRectangle(cornerRadius: BrowserDesign.Radius.control).fill(hovered ? palette.hover : .clear) }
        }
        .onHover { hovered = $0 }
        .accessibilityElement(children: .contain)
        .iconContextMenu { TabContextMenu(browser: browser, tab: tab) }
        .dropFrame(.tab(tab.id), in: layout)
    }

    /// The page it shows: away from its pinned page, a favorite's name would hide that it moved.
    private var title: some View {
        Text(verbatim: tab.shownTitle).lineLimit(1).truncationMode(.tail)
    }

    private func label(@ViewBuilder _ title: () -> some View) -> some View {
        HStack(spacing: BrowserDesign.rowInset) {
            FaviconView(cache: browser.favicons, key: browser.faviconKey(for: tab), size: BrowserDesign.tabIconSize, fetchingMissing: tab.isFavorite ? tab.url : nil) {
                Image(systemName: InternalPage(url: tab.url)?.symbol ?? "globe")
                    .font(BrowserDesign.Typography.chrome).foregroundStyle(.secondary)
            }
            .frame(width: BrowserDesign.rowIconWidth)
            title()
            Spacer(minLength: 0)
        }
        .padding(.leading, BrowserDesign.rowInset)
        .frame(height: BrowserDesign.tabRowHeight)
        .contentShape(Rectangle())
    }
}

/// Edits a favorite's pinned page as an address, in place of its name.
struct PinnedPageField: View {
    let browser: BrowserModel
    let tab: BrowserTab

    var body: some View {
        RenameField(name: tab.pinnedURL?.absoluteString ?? "", label: "Pinned Page") { browser.setPinnedPage(tab.id, to: $0) } end: {
            browser.window.endRenaming(.pinnedPage(tab.id))
        }
    }
}

/// Takes a favorite back to its pinned page, which its tooltip names: a return arrow, quiet in the sidebar's secondary
/// ink on a faint fill, brightening under the pointer, at the end of a row or a split's segment, or on a tile's corner.
struct PinnedPageReturn: View {
    enum Style { case inline, badge }

    let browser: BrowserModel
    let tab: BrowserTab
    let style: Style
    @State private var hovered = false
    @Environment(\.palette) private var palette
    @Environment(\.browserReduceMotion) private var reduceMotion

    var body: some View {
        Button { browser.returnToPinnedPage(tab.id) } label: { label }
            .buttonStyle(.plain)
            .foregroundStyle(hovered ? palette.ink : palette.secondary)
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : BrowserDesign.hover, value: hovered)
            .tooltip(String(localized: "Back to \(tab.pinnedName)"))
            .accessibilityLabel(Text("Back to \(tab.pinnedName)"))
            .accessibilityIdentifier("sidebar.backToPinnedPage")
    }

    @ViewBuilder private var label: some View {
        let glyph = Image(systemName: "arrow.uturn.backward")
        let fill = hovered ? palette.fill : palette.hover
        switch style {
        case .inline:
            glyph.font(.system(size: 9, weight: .semibold))
                .frame(width: 18, height: 18)
                .background(fill, in: Circle())
                .contentShape(Circle())
        case .badge:
            glyph.font(.system(size: 8, weight: .semibold))
                .frame(width: 16, height: 16)
                .background(.regularMaterial, in: Circle())
                .overlay { Circle().strokeBorder(palette.line) }
                .contentShape(Circle())
        }
    }
}
