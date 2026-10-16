import BrowserCore
import AppKit
import Observation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Declared in Info.plist; only Aero reads it, other apps receive the tab's address.
    static let aeroTab = UTType(exportedAs: "app.getaero.browser.tab")
}

/// Where a dropped tab lands: its place, before `before` or at the end.
struct TabDestination: Equatable {
    let place: TabPlace
    let before: UUID?
}

/// What is dragged from the sidebar: the tab or group picked up and, when it is part of the selection, the rest of
/// it, in sidebar order. Every space's page can take it (docs/BROWSING.md › Several tabs at once).
struct TabDrag: Equatable {
    /// The tab or group picked up, which the drag image shows.
    let picked: PinnedItem
    let items: [PinnedItem]
    let spaceID: UUID
    /// The tab shown as the drag began, shown again where it lands.
    let shownTabID: UUID?

    var tabIDs: [UUID] { items.compactMap { if case .tab(let id) = $0 { id } else { nil } } }
    /// Groups go only to a pinned list, so a drag with one takes everything there.
    var movesGroups: Bool { items.contains { if case .group = $0 { true } else { false } } }
}

/// Groups, with any tabs dragged along, over a space's page: shown where they would land in its pinned list.
struct PinnedDrop: Equatable {
    let items: [PinnedItem]
    let before: UUID?
}

/// Tabs dragged over a space's page, which shows them where they would land.
struct TabDrop: Equatable {
    let tabIDs: [UUID]
    let destination: TabDestination
}

/// Where a space's page shows its tabs and groups, in the page's coordinate space. Layout writes
/// the frames and drops read them, so a frame changing never redraws the page.
@MainActor @Observable
final class TabDropLayout {
    nonisolated static let space = "sidebar.page"
    /// How close to a side of the page a drag rests, and how long, to go to the space beyond it.
    static let edgeWidth: CGFloat = 18
    static let edgeDelay = Duration.milliseconds(550)

    enum Target: Hashable {
        case tab(UUID)
        case groupHeader(UUID)
        case section(TabPlace)
    }

    /// What a drag rests on: a side of the page, toward a neighbouring space, or a closed group, to open it.
    enum Rest: Equatable {
        case edge(HorizontalEdge)
        case group(UUID)
    }

    private(set) var resting: Rest?
    var edge: HorizontalEdge? { if case .edge(let edge) = resting { edge } else { nil } }
    @ObservationIgnored var rightToLeft = false
    @ObservationIgnored var frames: [Target: CGRect] = [:]
    @ObservationIgnored private var restTask: Task<Void, Never>?

    /// Which side of a page `width` wide `point` rests on, in reading direction.
    func edge(at point: CGPoint, width: CGFloat) -> HorizontalEdge? {
        guard width > 2 * Self.edgeWidth else { return nil }
        let left = point.x < Self.edgeWidth, right = point.x > width - Self.edgeWidth
        guard left || right else { return nil }
        return left != rightToLeft ? .leading : .trailing
    }

    /// Resting on `target` for `edgeDelay` runs `act` once; moving off it, or onto another, starts over.
    func rest(on target: Rest?, act: @escaping @MainActor (Rest) -> Void) {
        guard target != resting else { return }
        resting = target
        restTask?.cancel()
        guard let target else { restTask = nil; return }
        restTask = Task { [weak self] in
            do { try await Task.sleep(for: Self.edgeDelay) } catch { return }
            self?.resting = nil
            act(target)
        }
    }

    func stopResting() { rest(on: nil) { _ in } }

    isolated deinit { restTask?.cancel() }

    /// The share of a group header, at its top and, closed, at its bottom, that drops beside the group rather than in it.
    private static let headerEdge: CGFloat = 0.25

    /// The closed group whose header's middle, the part that drops into it, is under `point`.
    func closedGroup(at point: CGPoint, in tabs: SidebarTabs) -> UUID? {
        tabs.groups.first { group in
            guard group.group.isCollapsed, let frame = frames[.groupHeader(group.group.id)] else { return false }
            return frame.insetBy(dx: 0, dy: frame.height * Self.headerEdge).contains(point)
        }?.group.id
    }

    /// Where dragged groups and tabs go in the pinned list: before the first other entry, group or loose favorite,
    /// whose middle is below `point`, else last. Over one of their gaps they keep `current`.
    func pinnedDestination(at point: CGPoint, for items: [PinnedItem], in tabs: SidebarTabs, current: PinnedDrop?) -> PinnedDrop {
        let dragged = Set(items.map(\.id))
        if let current, tabs.pinned.contains(where: { dragged.contains($0.id) && frame(of: $0)?.contains(point) == true }) { return current }
        let before = tabs.pinned.first { item in
            guard !dragged.contains(item.id) else { return false }
            return frame(of: item).map { point.y < $0.midY } ?? false
        }?.id
        return PinnedDrop(items: items, before: before)
    }

    /// The tab or group under `point`. A dragged tab's own frame is a gap already shown, so it
    /// keeps `current`: the tiles moving aside never retarget a still pointer. In the pinned list a drop can land
    /// before or after a group as well as a tab; a group's header takes it in, except at its top quarter, which
    /// drops before the group, and a closed group's bottom quarter, which drops after it.
    func destination(at point: CGPoint, for dragged: [UUID], in tabs: SidebarTabs, current: TabDestination?) -> TabDestination? {
        // Resolve grid slots from geometry, not the tiles animating through them. Removing the
        // dragged item leaves a stable order, so a stationary pointer cannot oscillate slots.
        if let frame = frames[.section(.grid)], frame.contains(point), frame.width > 0 {
            let columns = FavoritesGrid.columnCount(in: frame.width)
            let spacing = FavoritesGrid.spacing
            let width = FavoritesGrid.tileWidth(in: frame.width)
            let x = rightToLeft ? frame.maxX - point.x : point.x - frame.minX
            let column = min(columns, max(0, Int((x + width / 2 + spacing) / (width + spacing))))
            let row = max(0, Int((point.y - frame.minY) / (FavoritesGrid.tileHeight + spacing)))
            let others = tabs.grid.filter { !dragged.contains($0.id) }
            let index = min(row * columns + column, others.count)
            return TabDestination(place: .grid, before: index < others.count ? others[index].id : nil)
        }
        if dragged.contains(where: { frames[.tab($0)]?.contains(point) == true }) { return current }

        let pinned = tabs.pinned.filter { !dragged.contains($0.id) }
        for (index, item) in pinned.enumerated() {
            let next = pinned.indices.contains(index + 1) ? pinned[index + 1].id : nil
            switch item {
            case .tab(let tab):
                if let row = rowFrame(of: tab.id), row.contains(point) {
                    return TabDestination(place: .list(group: nil), before: point.y > row.midY ? next : tab.id)
                }
            case .group(let group, let members):
                let members = members.filter { !dragged.contains($0.id) }
                if let header = frames[.groupHeader(group.id)], header.contains(point) {
                    let edge = header.height * Self.headerEdge
                    if point.y < header.minY + edge { return TabDestination(place: .list(group: nil), before: group.id) }
                    if group.isCollapsed, point.y > header.maxY - edge { return TabDestination(place: .list(group: nil), before: next) }
                    return TabDestination(place: .list(group: group.id), before: group.isCollapsed ? nil : members.first?.id)
                }
                guard !group.isCollapsed else { continue }
                if let destination = rowDestination(at: point, among: members, in: .list(group: group.id)) { return destination }
            }
        }
        if let destination = rowDestination(at: point, among: tabs.open.filter { !dragged.contains($0.id) }, in: .open) { return destination }
        for group in tabs.groups where frames[.section(.list(group: group.group.id))]?.contains(point) == true {
            return TabDestination(place: .list(group: group.group.id), before: nil)
        }
        // The line under the pinned list takes drops for its end.
        if frames[.section(.list(group: nil))]?.contains(point) == true { return TabDestination(place: .list(group: nil), before: nil) }
        if let open = frames[.section(.open)], open.contains(point) {
            let first = tabs.open.first { !dragged.contains($0.id) }
            let above = first.flatMap { frames[.tab($0.id)] }.map { point.y < $0.minY } ?? false
            return TabDestination(place: .open, before: above ? first?.id : nil)
        }
        if let open = frames[.section(.open)], point.y > open.maxY { return TabDestination(place: .open, before: nil) }
        return current
    }

    /// A row's frame, grown to meet its neighbours, so the spacing between rows targets one of them.
    private func rowFrame(of id: UUID) -> CGRect? {
        frames[.tab(id)]?.insetBy(dx: 0, dy: -SidebarTabs.rowSpacing / 2)
    }

    /// Before the row under `point`, or after it in its lower half.
    private func rowDestination(at point: CGPoint, among rows: [BrowserTab], in place: TabPlace) -> TabDestination? {
        for (index, tab) in rows.enumerated() {
            guard let frame = rowFrame(of: tab.id), frame.contains(point) else { continue }
            let next = rows.indices.contains(index + 1) ? rows[index + 1].id : nil
            return TabDestination(place: place, before: point.y > frame.midY ? next : tab.id)
        }
        return nil
    }

    private func frame(of item: SidebarTabs.Pinned) -> CGRect? {
        switch item {
        case .tab(let tab): frames[.tab(tab.id)]
        case .group(let group, _): frames[.section(.list(group: group.id))]
        }
    }
}

extension View {
    /// Picking a tab up arms every page's native drop target at once, without relying on SwiftUI session IDs; other
    /// apps receive its address.
    func tabDraggable(_ tab: BrowserTab, browser: BrowserModel) -> some View {
        onDrag {
            browser.beginDrag(.tab(tab.id))
            let provider = NSItemProvider(object: tab.url as NSURL)
            provider.registerAeroItem(tab.id)
            return provider
        }
        .dragConfiguration(DragConfiguration(operationsWithinApp: .init(allowCopy: false, allowMove: true)))
    }

    /// A group carries no address, so it never leaves Aero.
    func groupDraggable(_ group: TabGroup, browser: BrowserModel) -> some View {
        onDrag {
            browser.beginDrag(.group(group.id))
            let provider = NSItemProvider()
            provider.registerAeroItem(group.id)
            return provider
        }
        .dragConfiguration(DragConfiguration(operationsWithinApp: .init(allowCopy: false, allowMove: true)))
    }

    func dropFrame(_ target: TabDropLayout.Target, in layout: TabDropLayout) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named(TabDropLayout.space)) } action: { layout.frames[target] = $0 }
    }
}

private extension NSItemProvider {
    /// Only Aero reads it: the drop itself reads `BrowserWindowState.tabDrag`.
    func registerAeroItem(_ id: UUID) {
        let data = Data(id.uuidString.utf8)
        registerDataRepresentation(forTypeIdentifier: UTType.aeroTab.identifier, visibility: .ownProcess) { completion in
            completion(data, nil)
            return nil
        }
    }
}
