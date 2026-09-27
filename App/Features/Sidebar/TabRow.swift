import BrowserCore
import SwiftUI

/// One shape shared by the selected row, so selection slides between rows instead of blinking.
struct SelectionHighlight: View {
    static let id = "sidebar.selection"
    let namespace: Namespace.ID
    @Environment(\.palette) private var palette

    var body: some View {
        RoundedRectangle(cornerRadius: BrowserDesign.Radius.control)
            .fill(palette.raised)
            .matchedGeometryEffect(id: Self.id, in: namespace)
    }
}

/// A favorite or an open tab in the sidebar's list. Closing a favorite only unloads it, hence its
/// minus; a dragged tab shows as a gap where it would land.
struct TabRow: View {
    let browser: BrowserModel
    let tab: BrowserTab
    let selected: Bool
    let lifted: Bool
    let selection: Namespace.ID
    let layout: TabDropLayout
    @State private var hovered = false
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            if browser.window.renaming == .tab(tab.id) {
                label {
                    RenameField(name: tab.displayTitle) { browser.renameTab(tab.id, to: $0) } end: { browser.window.endRenaming(.tab(tab.id)) }
                }
            } else {
                Button { browser.showTab(tab) } label: {
                    label { Text(verbatim: tab.displayTitle).lineLimit(1).truncationMode(.tail) }
                }
                .buttonStyle(.plain)
                .tabDraggable(tab)
                .accessibilityIdentifier(tab.isFavorite ? "sidebar.favorite" : "sidebar.tab")
            }
            Button {
                if tab.isFavorite && !browser.isTabOpen(tab) { browser.removeFavorite(tab.id) }
                else { browser.closeTab(tab.id) }
            } label: {
                Image(systemName: tab.isFavorite && browser.isTabOpen(tab) ? "minus" : "xmark").font(BrowserDesign.Typography.glyph)
                    .frame(width: 26, height: 30).contentShape(Rectangle())
            }
            .buttonStyle(QuietButtonStyle())
            .opacity(hovered || selected ? 1 : 0)
            .accessibilityLabel(tab.isFavorite && !browser.isTabOpen(tab) ? Text("Remove from Favorites") : Text("Close tab"))
            .accessibilityIdentifier(tab.isFavorite && !browser.isTabOpen(tab) ? "sidebar.removeFavorite" : "sidebar.closeTab")
        }
        .opacity(lifted ? 0 : 1)
        .background {
            if lifted { RoundedRectangle(cornerRadius: BrowserDesign.Radius.control).fill(palette.fill) }
            else if selected { SelectionHighlight(namespace: selection) }
            else { RoundedRectangle(cornerRadius: BrowserDesign.Radius.control).fill(hovered ? palette.hover : .clear) }
        }
        .onHover { hovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu { TabContextMenu(browser: browser, tab: tab) }
        .dropFrame(.tab(tab.id), in: layout)
    }

    private func label(@ViewBuilder _ title: () -> some View) -> some View {
        HStack(spacing: BrowserDesign.rowInset) {
            FaviconView(cache: browser.favicons, key: browser.faviconKey(for: tab), size: BrowserDesign.tabIconSize) {
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
