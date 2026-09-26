import BrowserCore
import SwiftUI

/// One profile's tabs in the sidebar: pinned tiles, New Tab and the tab list. Pages of other
/// profiles are records only; choosing a tab there switches to its profile.
struct ProfilePage: View {
    let browser: BrowserModel
    let profile: BrowserProfile
    let space: BrowserSpace
    @Namespace private var selection
    @State private var targetedTabID: UUID?
    @State private var endTargeted = false

    var body: some View {
        let tabs = browser.tabs(in: space)
        let isCurrent = profile.id == browser.window.selectedProfileID
        let selectedTabID = isCurrent ? browser.window.selectedTabID : nil
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                PinnedTabsGrid(browser: browser, pinned: tabs.filter(\.isPinned), selectedTabID: selectedTabID, select: select)

                Button { newTab() } label: {
                    HStack(spacing: BrowserDesign.rowInset) {
                        Image(systemName: "plus").frame(width: BrowserDesign.rowIconWidth)
                        Text("New tab")
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, BrowserDesign.rowInset)
                    .frame(height: BrowserDesign.controlHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(QuietButtonStyle())
                .accessibilityIdentifier("sidebar.newTab")

                if isCurrent, selectedTabID == nil {
                    HStack(spacing: BrowserDesign.rowInset) {
                        Image(systemName: "magnifyingglass").font(BrowserDesign.Typography.label).frame(width: BrowserDesign.rowIconWidth)
                        Text("New tab")
                        Spacer()
                    }
                    .padding(.horizontal, BrowserDesign.rowInset)
                    .frame(height: BrowserDesign.tabRowHeight)
                    .background { SelectionHighlight(namespace: selection) }
                    .accessibilityAddTraits(.isSelected)
                }
                ForEach(tabs.filter { !$0.isPinned }) { tab in
                    TabRow(tab: tab, selected: selectedTabID == tab.id, selection: selection,
                           select: { select(tab) }, close: { browser.closeTab(tab.id) }) {
                        FaviconView(cache: browser.favicons, key: browser.faviconKey(for: tab), size: BrowserDesign.tabIconSize) {
                            Image(systemName: InternalPage(url: tab.url)?.symbol ?? "globe")
                                .font(BrowserDesign.Typography.chrome).foregroundStyle(.secondary)
                        }
                    }
                    .contextMenu { TabContextMenu(tab: tab, browser: browser) }
                    .draggable(tab.dragItem)
                    .dropDestination(for: TabDragItem.self) { items, _ in
                        drop(items, before: tab.id)
                    } isTargeted: { targetedTabID = $0 ? tab.id : (targetedTabID == tab.id ? nil : targetedTabID) }
                    .overlay(alignment: .top) { if targetedTabID == tab.id { DropIndicator() } }
                }
                // The rest of the list accepts drops at the end.
                Color.clear
                    .frame(height: BrowserDesign.tabRowHeight)
                    .contentShape(Rectangle())
                    .dropDestination(for: TabDragItem.self) { items, _ in
                        drop(items, before: nil)
                    } isTargeted: { endTargeted = $0 }
                    .overlay(alignment: .top) { if endTargeted { DropIndicator() } }
                    .accessibilityHidden(true)
            }
            .browserAnimation(value: selectedTabID)
            .browserAnimation(value: tabs.map(\.id))
            .browserAnimation(value: tabs.map(\.isPinned))
            .padding(.horizontal, BrowserDesign.rowInset)
            .padding(.top, 12)
        }
        .scrollIndicators(.hidden)
    }

    private func select(_ tab: BrowserTab) {
        browser.switchProfile(profile.id)
        browser.selectTab(tab.id)
    }

    private func newTab() {
        browser.switchProfile(profile.id)
        browser.perform(.newTab)
    }

    private func drop(_ items: [TabDragItem], before targetID: UUID?) -> Bool {
        guard let item = items.first else { return false }
        browser.moveTab(item.tabID, before: targetID, pinned: false)
        return true
    }
}
