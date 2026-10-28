import AppKit
import BrowserCore
import SwiftUI
import UniformTypeIdentifiers

/// SwiftUI owns pickup; AppKit handles cancellation, the moving preview and synchronous drop. SwiftUI's own
/// `dropDestination` never commits a tab dropped in the sidebar, as `SidebarJourneys` shows, so the drop is AppKit's.
struct SidebarDropTarget: NSViewRepresentable {
    let browser: BrowserModel
    let layout: TabDropLayout
    let onMove: (CGPoint?) -> TabPlace?
    let onDrop: () -> Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.layoutDirection) private var layoutDirection

    func makeNSView(context: Context) -> DropView {
        let view = DropView()
        view.registerForDraggedTypes([NSPasteboard.PasteboardType(UTType.aeroTab.identifier)])
        return view
    }

    func updateNSView(_ view: DropView, context: Context) {
        layout.rightToLeft = layoutDirection == .rightToLeft
        view.isDragging = { browser.window.tabDrag != nil }
        view.onMove = onMove
        view.onDrop = onDrop
        view.onEnd = { browser.window.tabDrag = nil }
        view.makePreviews = {
            guard let drag = browser.window.tabDrag else { return nil }
            let palette = BrowserPalette(scheme: colorScheme)
            let width = layout.frames[.section(.open)]?.width ?? (BrowserDesign.sidebarWidth - 2 * BrowserDesign.sidebarInset)
            let rightToLeft = layoutDirection == .rightToLeft
            // A split's picked panes are one entry.
            let count = Set(drag.items.map { browser.session.split(containing: $0.id)?.id ?? $0.id }).count
            // A group shows as its header: the folder and its name, never as a tile.
            if case .group(let groupID) = drag.picked {
                guard let group = browser.session.spaces.lazy.flatMap(\.groups).first(where: { $0.id == groupID }) else { return nil }
                let folder = PreviewItem(title: group.name, icon: nil, symbol: "folder", initial: nil)
                let image = Self.preview([folder], count: count, grid: false, width: width, palette: palette, rightToLeft: rightToLeft)
                return (image, image)
            }
            // A split shows whole, as its row or its tile does.
            let panes = browser.session.split(containing: drag.picked.id)?.tabIDs ?? [drag.picked.id]
            let items = browser.tabs(panes).map { tab in
                let page = InternalPage(url: tab.url)
                return PreviewItem(title: tab.displayTitle, icon: browser.faviconKey(for: tab).flatMap { browser.favicons.favicon(for: $0).image },
                                   symbol: page?.symbol ?? "globe", initial: page == nil ? String(tab.url.siteName.prefix(1)).uppercased() : nil)
            }
            guard !items.isEmpty else { return nil }
            return (Self.preview(items, count: count, grid: false, width: width, palette: palette, rightToLeft: rightToLeft),
                    Self.preview(items, count: count, grid: true, width: width, palette: palette, rightToLeft: rightToLeft))
        }
    }

    /// A tab, a pane of a split or a group, as its preview draws it. Without a favicon a tile shows `initial` when there
    /// is one, else `symbol`.
    private struct PreviewItem {
        let title: String
        let icon: NSImage?
        let symbol: String
        let initial: String?
    }

    /// Native drawing avoids starting a SwiftUI render inside AppKit's mouse tracking loop. A split's panes show as the
    /// segments of its row or the stacked squares of its tile; several dragged entries show their count on the trailing
    /// top corner.
    private static func preview(_ items: [PreviewItem], count: Int, grid: Bool, width: CGFloat, palette: BrowserPalette,
                                rightToLeft: Bool) -> NSImage {
        let size = NSSize(width: grid ? FavoritesGrid.tileWidth(in: width) : width,
                          height: grid ? FavoritesGrid.tileHeight : BrowserDesign.tabRowHeight)
        let fill = NSColor(grid ? palette.favoriteTileHover : palette.raised)
        let border = NSColor(palette.line)
        let canvas = NSColor(palette.canvas)
        let ink = NSColor(palette.ink)
        return NSImage(size: size, flipped: false) { bounds in
            let radius = grid ? FavoritesGrid.radius : BrowserDesign.Radius.control
            let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
            fill.setFill()
            shape.fill()
            border.setStroke()
            shape.stroke()
            if grid, items.count > 1 {
                // Drawn last to first, so the first pane's square is on top.
                let side = SplitStack.side, step = side - SplitStack.overlap
                let total = side + step * CGFloat(items.count - 1)
                for (index, item) in items.enumerated().reversed() {
                    let offset = (size.width - total) / 2 + step * CGFloat(index)
                    let square = CGRect(x: rightToLeft ? size.width - offset - side : offset, y: (size.height - side) / 2, width: side, height: side)
                    let path = NSBezierPath(roundedRect: square.insetBy(dx: 0.5, dy: 0.5), xRadius: SplitStack.radius, yRadius: SplitStack.radius)
                    canvas.setFill()
                    path.fill()
                    border.setStroke()
                    path.stroke()
                    drawIcon(item, size: SplitStack.iconSize, centeredIn: square, ink: ink)
                }
            } else if grid {
                drawIcon(items[0], size: FavoritesGrid.iconSize, centeredIn: bounds, ink: ink)
            } else {
                // One segment per pane, as wide as the others, as the split's row shows them.
                let padding: CGFloat = items.count > 1 ? 4 : 0, spacing: CGFloat = 4
                let segment = (size.width - 2 * padding - spacing * CGFloat(items.count - 1)) / CGFloat(items.count)
                for (index, item) in items.enumerated() {
                    let offset = padding + (segment + spacing) * CGFloat(index)
                    let rect = CGRect(x: rightToLeft ? size.width - offset - segment : offset, y: 0, width: segment, height: size.height)
                    drawRow(item, in: rect, inset: items.count > 1 ? 6 : BrowserDesign.rowInset, ink: ink, rightToLeft: rightToLeft)
                }
            }
            if count > 1 { drawBadge(count, in: bounds, rightToLeft: rightToLeft) }
            return true
        }
    }

    private static func drawIcon(_ item: PreviewItem, size: CGFloat, centeredIn rect: CGRect, ink: NSColor) {
        let iconRect = CGRect(x: rect.midX - size / 2, y: rect.midY - size / 2, width: size, height: size)
        if item.icon == nil, let initial = item.initial {
            let fontSize = size * FavoritesGrid.placeholderSize / FavoritesGrid.iconSize
            let plain = NSFont.systemFont(ofSize: fontSize, weight: .medium)
            // The tile's rounded initial (`FavoritesGrid.initialFont`).
            let rounded = plain.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: fontSize) } ?? plain
            let attributes: [NSAttributedString.Key: Any] = [.font: rounded, .foregroundColor: ink]
            let text = initial as NSString
            let textSize = text.size(withAttributes: attributes)
            text.draw(at: CGPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2), withAttributes: attributes)
        } else if let image = item.icon ?? symbolImage(item.symbol, ink: ink) {
            image.draw(in: iconRect)
        }
    }

    /// A row's icon and title, the title cut short at the end of `rect`.
    private static func drawRow(_ item: PreviewItem, in rect: CGRect, inset: CGFloat, ink: NSColor, rightToLeft: Bool) {
        let iconSize = BrowserDesign.tabIconSize
        let iconX = rightToLeft ? rect.maxX - inset - iconSize : rect.minX + inset
        if let image = item.icon ?? symbolImage(item.symbol, ink: ink) {
            image.draw(in: CGRect(x: iconX, y: rect.midY - iconSize / 2, width: iconSize, height: iconSize))
        }
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let textHeight = ceil(font.ascender - font.descender)
        let textInset = inset * 2 + BrowserDesign.rowIconWidth
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = rightToLeft ? .right : .left
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph]
        let textWidth = max(0, rect.width - textInset - inset)
        let textRect = CGRect(x: rightToLeft ? rect.minX + inset : rect.minX + textInset, y: rect.midY - textHeight / 2, width: textWidth, height: textHeight)
        (item.title as NSString).draw(in: textRect, withAttributes: attributes)
    }

    private static func symbolImage(_ name: String, ink: NSColor) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(paletteColors: [ink]))
    }

    private static func drawBadge(_ count: Int, in bounds: CGRect, rightToLeft: Bool) {
        let text = count.formatted() as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: NSColor.white]
        let size = text.size(withAttributes: attributes)
        let height: CGFloat = 18
        let badgeWidth = max(height, size.width + 10)
        let x = rightToLeft ? bounds.minX + 4 : bounds.maxX - badgeWidth - 4
        let badge = CGRect(x: x, y: bounds.maxY - height - 4, width: badgeWidth, height: height)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: badge, xRadius: height / 2, yRadius: height / 2).fill()
        text.draw(at: CGPoint(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2), withAttributes: attributes)
    }

    final class DropView: NSView {
        var isDragging: () -> Bool = { false }
        var onMove: (CGPoint?) -> TabPlace? = { _ in nil }
        var onDrop: () -> Bool = { false }
        var onEnd: () -> Void = {}
        var makePreviews: () -> (NSImage, NSImage)? = { nil }
        private var previews: (NSImage, NSImage)?
        private var grid: Bool?

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? {
            isDragging() ? super.hitTest(point) : nil
        }

        override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
            previews = makePreviews()
            grid = nil
            return draggingUpdated(sender)
        }

        override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
            guard isDragging(), let previews else { return [] }
            let point = convert(sender.draggingLocation, from: nil)
            let asGrid = onMove(point) == .grid
            if grid != asGrid {
                grid = asGrid
                let image = asGrid ? previews.1 : previews.0
                sender.draggingFormation = .none
                sender.enumerateDraggingItems(options: [], for: self, classes: [NSPasteboardItem.self], searchOptions: [:]) { item, _, _ in
                    item.setDraggingFrame(CGRect(x: point.x - image.size.width / 2, y: point.y - image.size.height / 2,
                                                 width: image.size.width, height: image.size.height), contents: image)
                }
            }
            return .move
        }

        override func draggingExited(_ sender: (any NSDraggingInfo)?) {
            _ = onMove(nil)
            previews = nil
            grid = nil
        }

        override func draggingEnded(_ sender: any NSDraggingInfo) {
            _ = onMove(nil)
            onEnd()
            previews = nil
            grid = nil
        }

        override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { isDragging() }

        override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            _ = onMove(convert(sender.draggingLocation, from: nil))
            let accepted = onDrop()
            previews = nil
            grid = nil
            return accepted
        }
    }
}
