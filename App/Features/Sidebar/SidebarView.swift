import BrowserCore
import SwiftUI

struct SidebarView: View {
    let browser: BrowserModel
    @Namespace private var selection
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
                    Image(systemName: browser.selectedTab == nil ? "magnifyingglass" : "globe")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    if let tab = browser.selectedTab {
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
                    if !pinned.isEmpty {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                            ForEach(pinned) { tab in
                                Button { browser.selectTab(tab.id) } label: {
                                    FaviconView(cache: browser.favicons, key: browser.faviconKey(for: tab), size: BrowserDesign.pinnedIconSize) {
                                        Text(verbatim: siteInitial(tab))
                                            .font(.system(size: 18, weight: .medium, design: .rounded))
                                    }
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 48)
                                        .browserSurface(fill: BrowserPalette(scheme: scheme).raised,
                                                        border: BrowserPalette(scheme: scheme).line,
                                                        radius: BrowserDesign.Radius.card)
                                        .contentShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.card))
                                }
                                .buttonStyle(.plain)
                                .help(tab.sidebarTitle)
                                .accessibilityLabel(tab.sidebarTitle)
                                .contextMenu { tabActions(tab) }
                            }
                        }
                        .padding(.bottom, 12)
                    }

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
                        .frame(height: 34)
                        .background { SelectionHighlight(namespace: selection) }
                        .accessibilityAddTraits(.isSelected)
                    }
                    ForEach(browser.tabs.filter { !$0.isPinned }) { tab in
                        TabRow(tab: tab, selected: browser.window.selectedTabID == tab.id, selection: selection,
                               select: { browser.selectTab(tab.id) }, close: { browser.closeTab(tab.id) }) {
                            FaviconView(cache: browser.favicons, key: browser.faviconKey(for: tab), size: BrowserDesign.tabIconSize) {
                                Image(systemName: "globe").font(.system(size: 13)).foregroundStyle(.secondary)
                            }
                        }
                        .contextMenu { tabActions(tab) }
                    }
                }
                .animation(reduceMotion ? nil : BrowserDesign.motion, value: browser.window.selectedTabID)
                .padding(.horizontal, 10)
                .padding(.top, 12)
            }
            .scrollIndicators(.hidden)
        }
        .disabled(!browser.isReady)
    }

    private var pinned: [BrowserTab] { browser.tabs.filter(\.isPinned) }

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

    private func siteInitial(_ tab: BrowserTab) -> String {
        let name = tab.url.host?.replacingOccurrences(of: "www.", with: "") ?? tab.title
        return String(name.prefix(1)).uppercased()
    }

    @ViewBuilder private func tabActions(_ tab: BrowserTab) -> some View {
        Button(tab.isPinned ? "Unpin tab" : "Pin tab", systemImage: tab.isPinned ? "pin.slash" : "pin") { browser.togglePin(tab.id) }
        Button("Close tab", systemImage: "xmark") { browser.closeTab(tab.id) }
    }
}

/// One shape shared by the selected row, so selection slides between rows instead of blinking.
private struct SelectionHighlight: View {
    static let id = "sidebar.selection"
    let namespace: Namespace.ID
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        RoundedRectangle(cornerRadius: BrowserDesign.Radius.control)
            .fill(BrowserPalette(scheme: scheme).raised)
            .matchedGeometryEffect(id: Self.id, in: namespace)
    }
}

private struct TabRow<Icon: View>: View {
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
                .frame(height: 34)
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

private extension BrowserTab {
    var sidebarTitle: String {
        title.isEmpty ? url.host ?? url.absoluteString : title
    }
}
