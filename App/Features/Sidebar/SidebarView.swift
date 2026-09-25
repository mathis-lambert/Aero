import BrowserCore
import SwiftUI

struct SidebarView: View {
    let browser: BrowserModel
    @Namespace private var selection
    @State private var targetedTabID: UUID?
    @State private var endTargeted = false
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                NativeWindowControls().frame(width: BrowserDesign.windowControlsWidth)
                navigation
            }
            .frame(height: BrowserDesign.sidebarHeaderHeight)

            Button { browser.perform(.openLocation) } label: {
                HStack(spacing: 8) {
                    Image(systemName: browser.internalPage?.symbol ?? (browser.selectedTab == nil ? "magnifyingglass" : "globe"))
                        .font(BrowserDesign.Typography.label)
                        .foregroundStyle(.secondary)
                    if let page = browser.internalPage {
                        Text(verbatim: page.title).lineLimit(1)
                    } else if let tab = browser.selectedTab {
                        Text(verbatim: tab.url.siteName)
                            .lineLimit(1).truncationMode(.middle)
                    } else {
                        Text("Search or enter an address")
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .font(BrowserDesign.Typography.chrome)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(palette.fill, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
                .contentShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open location")
            .accessibilityIdentifier("sidebar.location")
            .padding(.horizontal, BrowserDesign.rowInset)
            .padding(.top, 8)
            .padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    PinnedTabsGrid(browser: browser)

                    ProfileSwitcher(browser: browser)
                        .padding(.bottom, 6)

                    Hairline().padding(.horizontal, 4).padding(.bottom, 5)

                    Button { browser.perform(.newTab) } label: {
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
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sidebar.newTab")

                    if browser.window.selectedTabID == nil {
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
                    ForEach(unpinned) { tab in
                        TabRow(tab: tab, selected: browser.window.selectedTabID == tab.id, selection: selection,
                               select: { browser.selectTab(tab.id) }, close: { browser.closeTab(tab.id) }) {
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
                .browserAnimation(value: browser.window.selectedTabID)
                .browserAnimation(value: browser.tabs.map(\.id))
                .browserAnimation(value: browser.tabs.map(\.isPinned))
                .padding(.horizontal, BrowserDesign.rowInset)
                .padding(.top, 12)
            }
            .scrollIndicators(.hidden)

            if !browser.downloads.downloads.isEmpty {
                DownloadsSection(downloads: browser.downloads)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .browserAnimation(value: browser.downloads.downloads.isEmpty)
        .disabled(!browser.isReady)
    }

    private var unpinned: [BrowserTab] { browser.tabs.filter { !$0.isPinned } }

    private func drop(_ items: [TabDragItem], before targetID: UUID?) -> Bool {
        guard let item = items.first else { return false }
        browser.moveTab(item.tabID, before: targetID, pinned: false)
        return true
    }

    private var navigation: some View {
        HStack(spacing: 0) {
            IconButton(symbol: "sidebar.left", label: "Toggle sidebar", size: BrowserDesign.navigationButtonSize) { browser.perform(.toggleSidebar) }
                .accessibilityIdentifier("sidebar.toggle")
            IconButton(symbol: "chevron.left", label: "Back", size: BrowserDesign.navigationButtonSize) { browser.perform(.back) }
                .disabled(!browser.isEnabled(.back))
                .accessibilityIdentifier("sidebar.back")
            IconButton(symbol: "chevron.right", label: "Forward", size: BrowserDesign.navigationButtonSize) { browser.perform(.forward) }
                .disabled(!browser.isEnabled(.forward))
                .accessibilityIdentifier("sidebar.forward")
            IconButton(symbol: browser.currentPage?.isLoading == true ? "xmark" : "arrow.clockwise", label: browser.currentPage?.isLoading == true ? "Stop loading" : "Reload page", size: BrowserDesign.navigationButtonSize) {
                if browser.currentPage?.isLoading == true { browser.currentPage?.stop() }
                else { browser.perform(.reload) }
            }
            .disabled(browser.currentPage == nil)
            .accessibilityIdentifier("sidebar.reload")
        }
    }
}
