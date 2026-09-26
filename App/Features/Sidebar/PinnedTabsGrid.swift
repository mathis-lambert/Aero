import BrowserCore
import SwiftUI

/// Pinned tabs as compact tiles. Dropping a tab on a tile pins it before that tile; while the
/// grid is empty, a thin zone opens into a tile-sized target.
struct PinnedTabsGrid: View {
    private static let columns = 3
    private static let spacing: CGFloat = 8
    private static let tileHeight: CGFloat = 48
    private static let emptyZoneHeight: CGFloat = 8
    /// The site initial, or a browser page's symbol, stands in for a missing favicon.
    private static let placeholderSize: CGFloat = 18
    private static let initialFont = Font.system(size: placeholderSize, weight: .medium, design: .rounded)

    let browser: BrowserModel
    let pinned: [BrowserTab]
    let selectedTabID: UUID?
    let select: (BrowserTab) -> Void
    @State private var targetedTabID: UUID?
    @State private var emptyZoneTargeted = false
    @Environment(\.palette) private var palette

    var body: some View {
        if pinned.isEmpty {
            RoundedRectangle(cornerRadius: BrowserDesign.Radius.card)
                .strokeBorder(.tint, style: StrokeStyle(lineWidth: 1, dash: [4]))
                .opacity(emptyZoneTargeted ? 1 : 0)
                .frame(height: emptyZoneTargeted ? Self.tileHeight : Self.emptyZoneHeight)
                .contentShape(Rectangle())
                .dropDestination(for: TabDragItem.self) { items, _ in
                    drop(items, before: nil)
                } isTargeted: { emptyZoneTargeted = $0 }
                .padding(.bottom, emptyZoneTargeted ? 12 : 0)
                .accessibilityHidden(true)
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.spacing), count: Self.columns), spacing: Self.spacing) {
                ForEach(pinned) { tab in tile(tab) }
            }
            .padding(.bottom, 12)
        }
    }

    private func tile(_ tab: BrowserTab) -> some View {
        let selected = selectedTabID == tab.id
        return Button { select(tab) } label: {
            FaviconView(cache: browser.favicons, key: browser.faviconKey(for: tab), size: BrowserDesign.pinnedIconSize) {
                if let page = InternalPage(url: tab.url) {
                    Image(systemName: page.symbol).font(.system(size: Self.placeholderSize)).foregroundStyle(.secondary)
                } else {
                    Text(verbatim: initial(tab)).font(Self.initialFont)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.tileHeight)
            .browserSurface(fill: palette.raised,
                            border: targetedTabID == tab.id || selected ? Color.accentColor : palette.line,
                            radius: BrowserDesign.Radius.card)
            .contentShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.card))
        }
        .buttonStyle(QuietButtonStyle(radius: BrowserDesign.Radius.card))
        .tooltip(tab.displayTitle)
        .accessibilityLabel(tab.displayTitle)
        .accessibilityIdentifier("sidebar.pinned")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu { TabContextMenu(tab: tab, browser: browser) }
        .draggable(tab.dragItem)
        .dropDestination(for: TabDragItem.self) { items, _ in
            drop(items, before: tab.id)
        } isTargeted: { targetedTabID = $0 ? tab.id : (targetedTabID == tab.id ? nil : targetedTabID) }
    }

    private func drop(_ items: [TabDragItem], before targetID: UUID?) -> Bool {
        guard let item = items.first else { return false }
        browser.moveTab(item.tabID, before: targetID, pinned: true)
        return true
    }

    private func initial(_ tab: BrowserTab) -> String {
        String(tab.url.siteName.prefix(1)).uppercased()
    }
}
