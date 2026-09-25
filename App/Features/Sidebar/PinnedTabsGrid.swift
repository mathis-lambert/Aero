import BrowserCore
import SwiftUI

/// Pinned tabs as compact tiles. Dropping a tab on a tile pins it before that tile; while the
/// grid is empty, a thin zone above the profile switcher opens into a tile-sized target.
struct PinnedTabsGrid: View {
    private static let columns = 3
    private static let spacing: CGFloat = 8
    private static let tileHeight: CGFloat = 48
    private static let emptyZoneHeight: CGFloat = 8

    let browser: BrowserModel
    @State private var targetedTabID: UUID?
    @State private var emptyZoneTargeted = false
    @Environment(\.colorScheme) private var scheme

    private var pinned: [BrowserTab] { browser.tabs.filter(\.isPinned) }

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
        let selected = browser.window.selectedTabID == tab.id
        return Button { browser.selectTab(tab.id) } label: {
            FaviconView(cache: browser.favicons, key: browser.faviconKey(for: tab), size: BrowserDesign.pinnedIconSize) {
                if let page = InternalPage(url: tab.url) {
                    Image(systemName: page.symbol).font(.system(size: 17)).foregroundStyle(.secondary)
                } else {
                    Text(verbatim: initial(tab)).font(.system(size: 18, weight: .medium, design: .rounded))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.tileHeight)
            .browserSurface(fill: BrowserPalette(scheme: scheme).raised,
                            border: targetedTabID == tab.id || selected ? Color.accentColor : BrowserPalette(scheme: scheme).line,
                            radius: BrowserDesign.Radius.card)
            .contentShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.card))
        }
        .buttonStyle(.plain)
        .help(tab.sidebarTitle)
        .accessibilityLabel(tab.sidebarTitle)
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
        let name = tab.url.host?.replacingOccurrences(of: "www.", with: "") ?? tab.title
        return String(name.prefix(1)).uppercased()
    }
}
