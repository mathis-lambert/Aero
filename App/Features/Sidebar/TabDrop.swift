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

/// A tab dragged over a space's page, which shows it where it would land.
struct TabDrop: Equatable {
    let tabID: UUID
    let destination: TabDestination
}

/// Where a space's page shows its tabs and groups, in the page's coordinate space. Layout writes
/// the frames and drops read them, so a frame changing never redraws the page.
@MainActor @Observable
final class TabDropLayout {
    nonisolated static let space = "sidebar.page"

    enum Target: Hashable {
        case tab(UUID)
        case groupHeader(UUID)
        case section(TabPlace)
    }

    var draggedTabID: UUID?
    @ObservationIgnored var rightToLeft = false
    @ObservationIgnored var frames: [Target: CGRect] = [:]

    /// The tab or group under `point`. The dragged tab's own frame is the gap already shown, so it
    /// keeps `current`: the tiles moving aside never retarget a still pointer.
    func destination(at point: CGPoint, for tabID: UUID, in tabs: SidebarTabs, current: TabDestination?) -> TabDestination? {
        // Resolve grid slots from geometry, not the tiles animating through them. Removing the
        // dragged item leaves a stable order, so a stationary pointer cannot oscillate slots.
        if let frame = frames[.section(.grid)], frame.contains(point), frame.width > 0 {
            let columns = FavoritesGrid.columnCount(in: frame.width)
            let spacing = FavoritesGrid.spacing
            let width = FavoritesGrid.tileWidth(in: frame.width)
            let x = rightToLeft ? frame.maxX - point.x : point.x - frame.minX
            let column = min(columns, max(0, Int((x + width / 2 + spacing) / (width + spacing))))
            let row = max(0, Int((point.y - frame.minY) / (FavoritesGrid.tileHeight + spacing)))
            let others = tabs.grid.filter { $0.id != tabID }
            let index = min(row * columns + column, others.count)
            return TabDestination(place: .grid, before: index < others.count ? others[index].id : nil)
        }
        if frames[.tab(tabID)]?.contains(point) == true { return current }
        for section in tabs.sections where section.place != .grid {
            let others = section.tabs.filter { $0.id != tabID }
            for (index, tab) in others.enumerated() {
                guard let frame = frames[.tab(tab.id)]?.insetBy(dx: 0, dy: -SidebarTabs.rowSpacing / 2), frame.contains(point) else { continue }
                let next = others.indices.contains(index + 1) ? others[index + 1].id : nil
                return TabDestination(place: section.place, before: point.y > frame.midY ? next : tab.id)
            }
        }
        for group in tabs.groups where frames[.groupHeader(group.group.id)]?.contains(point) == true {
            return TabDestination(place: .list(group: group.group.id), before: nil)
        }
        for section in tabs.sections where frames[.section(section.place)]?.contains(point) == true {
            let first = section.tabs.first { $0.id != tabID }
            let above = first.flatMap { frames[.tab($0.id)] }.map { point.y < $0.minY } ?? false
            return TabDestination(place: section.place, before: above ? first?.id : nil)
        }
        if let open = frames[.section(.open)], point.y > open.maxY { return TabDestination(place: .open, before: nil) }
        return current
    }
}

extension View {
    func tabDraggable(_ tab: BrowserTab, in layout: TabDropLayout) -> some View {
        onDrag {
            // Activate the native destination at pickup, without relying on SwiftUI session IDs.
            layout.draggedTabID = tab.id
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            let provider = NSItemProvider(object: tab.url as NSURL)
            let data = Data(tab.id.uuidString.utf8)
            provider.registerDataRepresentation(forTypeIdentifier: UTType.aeroTab.identifier, visibility: .ownProcess) { completion in
                completion(data, nil)
                return nil
            }
            return provider
        }
            .dragConfiguration(DragConfiguration(operationsWithinApp: .init(allowCopy: false, allowMove: true)))
    }

    func dropFrame(_ target: TabDropLayout.Target, in layout: TabDropLayout) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named(TabDropLayout.space)) } action: { layout.frames[target] = $0 }
    }
}
