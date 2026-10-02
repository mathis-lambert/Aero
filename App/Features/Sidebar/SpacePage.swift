import AppKit
import BrowserCore
import SwiftUI

/// One space's tabs in the sidebar: its favorites (the grid, then groups and loose rows in any order), a line,
/// then New Tab and its open tabs. Tabs dragged over the page, from this space or another, are shown
/// where they would land, and so is a dragged group. Resting on a side of the page goes to the
/// space beyond it; resting a tab on a closed group opens it, until the drag ends elsewhere.
/// Neighboring sidebars render records without creating website pages.
/// See docs/BROWSING.md › Favorites and open tabs.
struct SpacePage: View, @MainActor Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.browser === rhs.browser && lhs.space == rhs.space }
    let browser: BrowserModel
    let space: BrowserSpace
    @Namespace private var selection
    @State private var drop: TabDrop?
    @State private var pinnedDrop: PinnedDrop?
    /// Groups a drag opened, closed again unless the tabs land in them.
    @State private var springOpened: Set<UUID> = []
    @State private var layout = TabDropLayout()
    @State private var width: CGFloat = 0
    @Environment(\.palette) private var palette

    var body: some View {
        let tabs = SidebarTabs(session: browser.session, space: space, drop: drop, pinnedDrop: pinnedDrop)
        let isCurrent = space.id == browser.window.selectedSpaceID
        let selectedTabID = isCurrent ? browser.window.selectedTabID : nil
        let marked = isCurrent ? Set(browser.window.tabSelection.ids) : []
        let lifted = Set((drop?.tabIDs ?? []) + (pinnedDrop?.items.map(\.id) ?? []))
        let dragging = browser.window.tabDrag != nil
        let draggingTabs = browser.window.tabDrag.map { !$0.movesGroups } ?? false
        let targetedGroup: UUID? = if case .list(let group?) = drop?.destination.place { group } else { nil }
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

                FavoritesGrid(browser: browser, tabs: tabs.grid, selectedTabID: selectedTabID, marked: marked, lifted: lifted, dragging: draggingTabs, layout: layout)
                    .dropFrame(.section(.grid), in: layout)

                // Groups and loose favorites, in any order.
                ForEach(tabs.pinned) { item in
                    switch item {
                    case .tab(let tab): row(tab, selectedTabID: selectedTabID, marked: marked, lifted: lifted)
                    case .group(let group, let tabs):
                        TabGroupSection(browser: browser, group: group, tabs: tabs, selectedTabID: selectedTabID, marked: marked, lifted: lifted,
                                        isMarked: marked.contains(group.id), isLifted: lifted.contains(group.id), isTargeted: targetedGroup == group.id,
                                        selection: selection, layout: layout)
                            .dropFrame(.section(.list(group: group.id)), in: layout)
                    }
                }

                // The line takes drops for the end of the pinned list, which may be empty.
                Divider().padding(.vertical, 6)
                    .frame(minHeight: tabs.pinned.isEmpty ? 30 : nil)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("sidebar.pinnedDropZone")
                    .dropFrame(.section(.list(group: nil)), in: layout)

                VStack(alignment: .leading, spacing: SidebarTabs.rowSpacing) {
                    newTabButton(selected: isCurrent && selectedTabID == nil)
                    ForEach(tabs.open) { row($0, selectedTabID: selectedTabID, marked: marked, lifted: lifted) }
                }
                .dropFrame(.section(.open), in: layout)
            }
            .browserAnimation(value: selectedTabID)
            .browserAnimation(value: tabs.order)
            .browserAnimation(value: dragging)
            .browserAnimation(value: marked)
            .browserAnimation(value: space.groups)
            .padding(.horizontal, BrowserDesign.rowInset)
            .padding(.top, 12)
        }
        .tint(space.color.tint)
        .accentColor(space.color.tint)
        .scrollIndicators(.hidden)
        .coordinateSpace(.named(TabDropLayout.space))
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .overlay { if let edge = layout.edge { edgeGlow(edge) } }
        .overlay(SidebarDropTarget(browser: browser, layout: layout,
                                   onMove: { update(at: $0, tabs: tabs) }, onDrop: performDrop))
        .onChange(of: tabs.frameTargets, initial: true) { _, targets in
            layout.frames = layout.frames.filter { targets.contains($0.key) }
        }
        .onChange(of: dragging) { _, dragging in
            if !dragging {
                drop = nil
                pinnedDrop = nil
                layout.stopResting()
                for group in springOpened { browser.setGroupCollapsed(group, true) }
                springOpened = []
            }
        }
    }

    private func row(_ tab: BrowserTab, selectedTabID: UUID?, marked: Set<UUID>, lifted: Set<UUID>) -> some View {
        TabRow(browser: browser, tab: tab, selected: selectedTabID == tab.id, marked: marked.contains(tab.id),
               lifted: lifted.contains(tab.id), selection: selection, layout: layout)
    }

    /// The side a drag rests on takes a faint line of the next space's color, before the page slides to it.
    private func edgeGlow(_ edge: HorizontalEdge) -> some View {
        let color = neighbor(toward: edge)?.color.tint ?? palette.secondary
        return LinearGradient(colors: [color.opacity(0.22), color.opacity(0)],
                              startPoint: edge == .leading ? .leading : .trailing, endPoint: edge == .leading ? .trailing : .leading)
            .frame(width: 8)
            .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .top, endPoint: .bottom))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge == .leading ? .leading : .trailing)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .transition(.opacity)
    }

    /// The space before this one on the leading side, after it on the trailing side.
    private func neighbor(toward edge: HorizontalEdge) -> BrowserSpace? {
        let spaces = browser.session.spaces
        guard let index = spaces.firstIndex(where: { $0.id == space.id }) else { return nil }
        let next = index + (edge == .leading ? -1 : 1)
        return spaces.indices.contains(next) ? spaces[next] : nil
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
        guard let point, let drag = browser.window.tabDrag, space.id == browser.window.selectedSpaceID else {
            drop = nil
            pinnedDrop = nil
            layout.stopResting()
            return nil
        }
        let edge = layout.edge(at: point, width: width).flatMap { neighbor(toward: $0) == nil ? nil : $0 }
        let closed = drag.movesGroups ? nil : layout.closedGroup(at: point, in: tabs)
        layout.rest(on: edge.map(TabDropLayout.Rest.edge) ?? closed.map(TabDropLayout.Rest.group)) { rest in
            guard browser.window.tabDrag != nil, space.id == browser.window.selectedSpaceID else { return }
            switch rest {
            case .edge(let edge):
                guard let next = neighbor(toward: edge) else { return }
                drop = nil
                pinnedDrop = nil
                browser.switchSpace(next.id)
            case .group(let group):
                springOpened.insert(group)
                browser.setGroupCollapsed(group, false)
            }
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        if drag.movesGroups {
            let next = layout.pinnedDestination(at: point, for: drag.items, in: tabs, current: pinnedDrop)
            if next != pinnedDrop {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                pinnedDrop = next
            }
            return .list(group: nil)
        }
        let next = layout.destination(at: point, for: drag.tabIDs, in: tabs, current: drop?.destination)
            .map { TabDrop(tabIDs: drag.tabIDs, destination: $0) }
        if next != drop {
            if next != nil { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
            drop = next
        }
        return next?.destination.place
    }

    /// This local drop commits synchronously, before AppKit ends the drag and the target folds. Tabs from
    /// another space move here; a change of profile asks first.
    private func performDrop() -> Bool {
        defer { drop = nil; pinnedDrop = nil; browser.window.tabDrag = nil; layout.stopResting() }
        guard let drag = browser.window.tabDrag else { return false }
        // The page left after resting on its side stays AppKit's target until the pointer moves: released there,
        // the tabs go to the space now shown, as on its icon.
        if let shown = browser.window.selectedSpaceID, shown != space.id {
            if drag.movesGroups { browser.movePinned(drag.items, toSpace: shown, before: nil, showing: drag.shownTabID) }
            else { browser.moveTabs(drag.tabIDs, toSpace: shown, showing: drag.shownTabID) }
            return true
        }
        if drag.movesGroups {
            guard let pinnedDrop, pinnedDrop.items == drag.items else { return false }
            browser.movePinned(drag.items, toSpace: space.id, before: pinnedDrop.before, showing: drag.shownTabID)
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            return true
        }
        guard let drop, drag.tabIDs == drop.tabIDs else { return false }
        if case .list(let group?) = drop.destination.place { springOpened.remove(group) }
        if drag.spaceID == space.id {
            browser.moveTabs(drop.tabIDs, to: drop.destination.place, before: drop.destination.before)
            browser.window.tabSelection.clear()
        } else {
            browser.moveTabs(drop.tabIDs, toSpace: space.id, at: drop.destination, showing: drag.shownTabID)
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        return true
    }
}
