import AppKit
import BrowserCore
import SwiftUI

/// One space's tabs in the sidebar: its favorites (the grid, its groups and loose rows), a line,
/// then New Tab and its open tabs. A tab dragged over the page is shown where it would land.
/// Neighboring sidebars render records without creating website pages.
/// See docs/BROWSING.md › Favorites and open tabs.
struct SpacePage: View, @MainActor Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.browser === rhs.browser && lhs.space == rhs.space }
    let browser: BrowserModel
    let space: BrowserSpace
    @Namespace private var selection
    @State private var drop: TabDrop?
    @State private var layout = TabDropLayout()

    var body: some View {
        let tabs = SidebarTabs(session: browser.session, space: space, drop: drop)
        let isCurrent = space.id == browser.window.selectedSpaceID
        let selectedTabID = isCurrent ? browser.window.selectedTabID : nil
        let lifted = drop?.tabID
        ScrollView {
            VStack(alignment: .leading, spacing: SidebarTabs.rowSpacing) {
                HStack(alignment: .firstTextBaseline) {
                    Button { browser.showSettings(.space(space.id)) } label: {
                        HStack(spacing: 8) {
                            SpaceIcon(space: space, size: 13)
                            Text(verbatim: space.name).font(.headline).lineLimit(1)
                        }
                    }.buttonStyle(.plain)
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    Text(verbatim: browser.session.profiles.first { $0.id == space.profileID }?.name ?? "")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.horizontal, BrowserDesign.rowInset)
                .padding(.bottom, 8)

                FavoritesGrid(browser: browser, tabs: tabs.grid, selectedTabID: selectedTabID, lifted: lifted, layout: layout)
                    .dropFrame(.section(.grid), in: layout)

                ForEach(tabs.groups, id: \.group.id) { group, tabs in
                    TabGroupSection(browser: browser, group: group, tabs: tabs, selectedTabID: selectedTabID, lifted: lifted, selection: selection, layout: layout)
                        .dropFrame(.section(.list(group: group.id)), in: layout)
                }

                // The line takes drops for the loose favorites above it, which may be none.
                VStack(alignment: .leading, spacing: SidebarTabs.rowSpacing) {
                    ForEach(tabs.loose) { row($0, selectedTabID: selectedTabID, lifted: lifted) }
                    Divider().padding(.vertical, 6)
                        .frame(minHeight: tabs.loose.isEmpty ? 30 : nil)
                        .accessibilityIdentifier("sidebar.pinnedDropZone")
                }
                .dropFrame(.section(.list(group: nil)), in: layout)

                VStack(alignment: .leading, spacing: SidebarTabs.rowSpacing) {
                    newTabButton(selected: isCurrent && selectedTabID == nil)
                    ForEach(tabs.open) { row($0, selectedTabID: selectedTabID, lifted: lifted) }
                }
                .dropFrame(.section(.open), in: layout)
            }
            .browserAnimation(value: selectedTabID)
            .browserAnimation(value: tabs.order)
            .browserAnimation(value: layout.draggedTabID != nil)
            .browserAnimation(value: space.groups)
            .padding(.horizontal, BrowserDesign.rowInset)
            .padding(.top, 12)
        }
        .tint(space.color.tint)
        .accentColor(space.color.tint)
        .scrollIndicators(.hidden)
        .coordinateSpace(.named(TabDropLayout.space))
        .overlay(SidebarDropTarget(browser: browser, space: space, layout: layout,
                                   onMove: { update(at: $0, tabs: tabs) }, onDrop: performDrop))
        .onChange(of: tabs.frameTargets, initial: true) { _, targets in
            layout.frames = layout.frames.filter { targets.contains($0.key) }
        }
        .onChange(of: layout.draggedTabID) { _, id in if id == nil { drop = nil } }
    }

    private func row(_ tab: BrowserTab, selectedTabID: UUID?, lifted: UUID?) -> some View {
        TabRow(browser: browser, tab: tab, selected: selectedTabID == tab.id, lifted: lifted == tab.id, selection: selection, layout: layout)
    }

    private func newTabButton(selected: Bool) -> some View {
        Button {
            browser.switchSpace(space.id)
            browser.perform(.newTab)
        } label: {
            HStack(spacing: BrowserDesign.rowInset) {
                Image(systemName: "plus").frame(width: BrowserDesign.rowIconWidth)
                Text("New tab")
                Spacer()
            }
            .foregroundStyle(selected ? .primary : .secondary)
            .padding(.horizontal, BrowserDesign.rowInset)
            .frame(height: BrowserDesign.tabRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(QuietButtonStyle())
        .background { if selected { SelectionHighlight(namespace: selection) } }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("sidebar.newTab")
    }

    /// Native tracking also reports leaving the page and keeps the preview in sync with the gap.
    private func update(at point: CGPoint?, tabs: SidebarTabs) -> TabPlace? {
        guard let point, let tabID = layout.draggedTabID,
              browser.tabs(in: space).contains(where: { $0.id == tabID }) else {
            drop = nil
            return nil
        }
        let next = layout.destination(at: point, for: tabID, in: tabs, current: drop?.destination)
            .map { TabDrop(tabID: tabID, destination: $0) }
        if next != drop {
            if next != nil { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
            drop = next
        }
        return next?.destination.place
    }

    /// This local drop commits synchronously, before AppKit ends the drag and the target folds.
    private func performDrop() -> Bool {
        defer { drop = nil; layout.draggedTabID = nil }
        guard let drop, layout.draggedTabID == drop.tabID,
              browser.tabs(in: space).contains(where: { $0.id == drop.tabID }) else { return false }
        browser.moveTab(drop.tabID, to: drop.destination.place, before: drop.destination.before)
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        return true
    }
}
