import BrowserCore
import SwiftUI

struct SidebarView: View {
    let browser: BrowserModel
    @Namespace private var selection
    @State private var targetedTabID: UUID?
    @State private var endTargeted = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if let page = browser.internalPage {
                        Text(verbatim: page.title).lineLimit(1)
                    } else if let tab = browser.selectedTab {
                        Text(verbatim: tab.url.host ?? tab.url.absoluteString)
                            .lineLimit(1).truncationMode(.middle)
                    } else {
                        Text("Search or enter an address")
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .font(BrowserDesign.bodyFont)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
                .contentShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open location")
            .accessibilityIdentifier("sidebar.location")
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .padding(.bottom, 4)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    PinnedTabsGrid(browser: browser)

                    ProfileSwitcher(browser: browser)
                        .padding(.bottom, 6)

                    Rectangle().fill(BrowserPalette(scheme: scheme).line).frame(height: 1)
                        .padding(.horizontal, 4).padding(.bottom, 5)

                    Button { browser.perform(.newTab) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus").frame(width: BrowserDesign.rowIconWidth)
                            Text("New tab")
                            Spacer()
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("sidebar.newTab")

                    if browser.window.selectedTabID == nil {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass").font(.system(size: 12)).frame(width: BrowserDesign.rowIconWidth)
                            Text("New tab")
                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .frame(height: BrowserDesign.tabRowHeight)
                        .background { SelectionHighlight(namespace: selection) }
                        .accessibilityAddTraits(.isSelected)
                    }
                    ForEach(unpinned) { tab in
                        TabRow(tab: tab, selected: browser.window.selectedTabID == tab.id, selection: selection,
                               select: { browser.selectTab(tab.id) }, close: { browser.closeTab(tab.id) }) {
                            FaviconView(cache: browser.favicons, key: browser.faviconKey(for: tab), size: BrowserDesign.tabIconSize) {
                                Image(systemName: InternalPage(url: tab.url)?.symbol ?? "globe")
                                    .font(.system(size: 13)).foregroundStyle(.secondary)
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
                .animation(reduceMotion ? nil : BrowserDesign.motion, value: browser.window.selectedTabID)
                .animation(reduceMotion ? nil : BrowserDesign.motion, value: browser.tabs.map(\.id))
                .animation(reduceMotion ? nil : BrowserDesign.motion, value: browser.tabs.map(\.isPinned))
                .padding(.horizontal, 10)
                .padding(.top, 12)
            }
            .scrollIndicators(.hidden)

            if !browser.downloads.downloads.isEmpty {
                DownloadsSection(downloads: browser.downloads)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : BrowserDesign.motion, value: browser.downloads.downloads.isEmpty)
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
