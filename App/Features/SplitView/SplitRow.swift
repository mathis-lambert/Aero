import AppKit
import BrowserCore
import SwiftUI

/// A tab's row in the sidebar's list, or a split's.
struct EntryRow: View {
    let browser: BrowserModel
    let entry: SidebarTabs.Entry
    let selectedTabID: UUID?
    let marked: Set<UUID>
    let lifted: Set<UUID>
    let selection: Namespace.ID
    let layout: TabDropLayout

    var body: some View {
        switch entry {
        case .tab(let tab):
            TabRow(browser: browser, tab: tab, selected: selectedTabID == tab.id, marked: marked.contains(tab.id),
                   lifted: lifted.contains(tab.id), selection: selection, layout: layout)
        case .split(let split, let panes):
            SplitRow(browser: browser, split: split, panes: panes, focusedTabID: selectedTabID, lifted: lifted.contains(entry.id),
                     selection: selection, layout: layout)
        }
    }
}

/// A split in the sidebar (docs/SPLIT_VIEW.md): one row, a segment per pane, in reading order, each as wide as the
/// others with its favicon and title. It is kept, dragged and moved as one tab, by any of its segments. A click on a
/// segment shows the split with that pane focused. Under the pointer each segment offers to close its pane.
struct SplitRow: View {
    let browser: BrowserModel
    let split: TabSplit
    let panes: [BrowserTab]
    let focusedTabID: UUID?
    let lifted: Bool
    let selection: Namespace.ID
    let layout: TabDropLayout
    @State private var hovered = false
    @Environment(\.palette) private var palette
    @Environment(\.browserReduceMotion) private var reduceMotion

    var body: some View {
        let selected = panes.contains { $0.id == focusedTabID }
        HStack(spacing: 4) {
            ForEach(panes) { tab in segment(tab) }
        }
        .padding(.horizontal, 4)
        .frame(height: BrowserDesign.tabRowHeight)
        .opacity(lifted ? 0 : 1)
        .background {
            if lifted { RoundedRectangle(cornerRadius: BrowserDesign.Radius.control).fill(palette.fill) }
            else if selected { SelectionHighlight(namespace: selection) }
            else { RoundedRectangle(cornerRadius: BrowserDesign.Radius.control).fill(hovered ? palette.hover : .clear) }
        }
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : BrowserDesign.hover, value: hovered)
        // Taken by any segment, the whole row goes, its image too.
        .tabDraggable(panes[0], browser: browser)
        .iconContextMenu { SplitContextMenu(browser: browser, split: split, panes: panes) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: panes.map(\.displayTitle).formatted(.list(type: .and))))
        .accessibilityIdentifier(panes.first?.isFavorite == true ? "sidebar.favoriteSplit" : "sidebar.split")
        // Drops land before or after the split as a whole.
        .dropFrame(.tab(panes.first?.id ?? split.id), in: layout)
    }

    /// A pane's favicon and title, the title fading out where the segment ends, and its close button under the pointer.
    private func segment(_ tab: BrowserTab) -> some View {
        HStack(spacing: 2) {
            Button { browser.click(tab, modifiers: NSEvent.modifierFlags) } label: {
                HStack(spacing: 8) {
                    FaviconView(cache: browser.favicons, key: browser.faviconKey(for: tab), size: BrowserDesign.tabIconSize,
                                fetchingMissing: nil) {
                        Image(systemName: InternalPage(url: tab.url)?.symbol ?? "globe")
                            .font(BrowserDesign.Typography.chrome).foregroundStyle(.secondary)
                    }
                    .frame(width: BrowserDesign.rowIconWidth)
                    Text(verbatim: tab.shownTitle)
                        .lineLimit(1)
                        // Its whole width, clipped to the segment's: a long title never widens the row.
                        .fixedSize()
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                        .clipped()
                        .mask(alignment: .leading) {
                            HStack(spacing: 0) {
                                Color.black
                                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 14)
                            }
                        }
                }
                .padding(.leading, 6)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture(count: 2).onEnded { browser.returnToPinnedPage(tab.id) })
            .tooltip(tab.displayTitle)
            .accessibilityLabel(Text(verbatim: tab.displayTitle))
            .accessibilityAddTraits(tab.id == focusedTabID ? .isSelected : [])
            .accessibilityIdentifier("sidebar.split.pane")
            if tab.hasLeftPinnedPage { PinnedPageReturn(browser: browser, tab: tab, style: .inline) }
            if hovered {
                Button { browser.closeTab(tab.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.ink)
                        .frame(width: 24, height: 24)
                        .contentShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
                }
                .buttonStyle(QuietButtonStyle())
                .transition(.opacity)
                .accessibilityLabel("Close Tab")
                .accessibilityIdentifier("sidebar.split.closePane")
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity)
    }
}

/// What a split can do, from its row's or its tile's menu: what a tab can, for all its panes at once.
struct SplitContextMenu: View {
    let browser: BrowserModel
    let split: TabSplit
    let panes: [BrowserTab]

    var body: some View {
        if let lead = panes.first {
            Button("Separate Split View", systemImage: BrowserCommand.separateSplit.symbol) { browser.separateSplit(split.id) }
            Divider()
            TabPlaceMenu(browser: browser, tab: lead) { browser.removeFavorite(split: panes) }
            Divider()
            TabMoveMenus(browser: browser, tab: lead)
            if panes.contains(where: browser.isTabOpen) {
                Divider()
                Button("Close Split View", systemImage: "xmark") { browser.closeSplit(panes.map(\.id)) }
            }
        }
    }
}
