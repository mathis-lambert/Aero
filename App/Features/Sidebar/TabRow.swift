import BrowserCore
import SwiftUI

/// One shape shared by the selected row, so selection slides between rows instead of blinking.
struct SelectionHighlight: View {
    static let id = "sidebar.selection"
    let namespace: Namespace.ID
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: BrowserDesign.Radius.control)
            .fill(BrowserPalette(scheme: scheme).raised)
            .matchedGeometryEffect(id: Self.id, in: namespace)
    }
}

/// The insertion line shown above the element a tab would be dropped before.
struct DropIndicator: View {
    static let thickness: CGFloat = 2

    var body: some View {
        Capsule().fill(.tint).frame(height: Self.thickness).offset(y: -Self.thickness)
    }
}

struct TabRow<Icon: View>: View {
    let tab: BrowserTab
    let selected: Bool
    let selection: Namespace.ID
    let select: () -> Void
    let close: () -> Void
    @ViewBuilder let icon: Icon
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 0) {
            Button(action: select) {
                HStack(spacing: 10) {
                    icon.frame(width: BrowserDesign.rowIconWidth)
                    Text(verbatim: tab.sidebarTitle)
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 10)
                .frame(height: BrowserDesign.tabRowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("sidebar.tab")
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                    .frame(width: 26, height: 30).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hovered || selected ? 1 : 0)
            .accessibilityLabel("Close tab")
        }
        .background {
            if selected { SelectionHighlight(namespace: selection) }
            else { RoundedRectangle(cornerRadius: BrowserDesign.Radius.control).fill(.primary.opacity(hovered ? 0.04 : 0)) }
        }
        .onHover { hovered = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct TabContextMenu: View {
    let tab: BrowserTab
    let browser: BrowserModel

    var body: some View {
        Button(tab.isPinned ? "Unpin tab" : "Pin tab", systemImage: tab.isPinned ? "pin.slash" : "pin") { browser.togglePin(tab.id) }
        Button("Close tab", systemImage: "xmark") { browser.closeTab(tab.id) }
    }
}

extension BrowserTab {
    var sidebarTitle: String {
        if let page = InternalPage(url: url) { return page.title }
        return title.isEmpty ? url.host ?? url.absoluteString : title
    }

    var dragItem: TabDragItem { TabDragItem(tabID: id, url: url) }
}
