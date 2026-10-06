import AppKit
import BrowserCore
import SwiftUI
import UniformTypeIdentifiers

/// SwiftUI owns pickup; AppKit handles cancellation, the moving preview and synchronous drop. SwiftUI's own
/// `dropDestination` never commits a tab dropped in the sidebar, as `SidebarJourneys` shows, so the drop is AppKit's.
struct SidebarDropTarget: NSViewRepresentable {
    let browser: BrowserModel
    let space: BrowserSpace
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
        view.layout = layout
        view.onMove = onMove
        view.onDrop = onDrop
        view.makePreviews = {
            guard let id = layout.draggedTabID, let tab = browser.tabs(in: space).first(where: { $0.id == id }) else { return nil }
            let palette = BrowserPalette(scheme: colorScheme)
            let icon = browser.faviconKey(for: tab).flatMap { browser.favicons.favicon(for: $0).image }
            let width = layout.frames[.section(.open)]?.width ?? (BrowserDesign.sidebarWidth - 2 * BrowserDesign.rowInset)
            return (Self.preview(tab: tab, icon: icon, grid: false, width: width, palette: palette, rightToLeft: layoutDirection == .rightToLeft),
                    Self.preview(tab: tab, icon: icon, grid: true, width: width, palette: palette, rightToLeft: layoutDirection == .rightToLeft))
        }
    }

    /// Native drawing avoids starting a SwiftUI render inside AppKit's mouse tracking loop.
    private static func preview(tab: BrowserTab, icon: NSImage?, grid: Bool, width: CGFloat,
                                palette: BrowserPalette, rightToLeft: Bool) -> NSImage {
        let size = NSSize(width: grid ? FavoritesGrid.tileWidth(in: width) : width,
                          height: grid ? FavoritesGrid.tileHeight : BrowserDesign.tabRowHeight)
        let fill = NSColor(grid ? palette.favoriteTileHover : palette.raised)
        let border = NSColor(palette.line)
        let ink = NSColor(palette.ink)
        let iconSize = grid ? BrowserDesign.pinnedIconSize : BrowserDesign.tabIconSize
        let inset = BrowserDesign.rowInset
        let textInset = inset * 2 + BrowserDesign.rowIconWidth
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let textHeight = ceil(font.ascender - font.descender)
        let fallback = InternalPage(url: tab.url)?.symbol ?? "globe"
        let symbol = NSImage(systemSymbolName: fallback, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(paletteColors: [ink]))
        return NSImage(size: size, flipped: false) { bounds in
            let radius = grid ? BrowserDesign.Radius.card : BrowserDesign.Radius.control
            let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: radius, yRadius: radius)
            fill.setFill()
            shape.fill()
            border.setStroke()
            shape.stroke()
            let x = grid ? (size.width - iconSize) / 2 : rightToLeft ? size.width - inset - iconSize : inset
            let iconRect = CGRect(x: x, y: (size.height - iconSize) / 2, width: iconSize, height: iconSize)
            if grid, icon == nil, InternalPage(url: tab.url) == nil {
                let text = String(tab.url.siteName.prefix(1)).uppercased() as NSString
                let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 18, weight: .medium), .foregroundColor: ink]
                let textSize = text.size(withAttributes: attributes)
                text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: (size.height - textSize.height) / 2), withAttributes: attributes)
            } else if let image = icon ?? symbol {
                image.draw(in: iconRect)
            }
            if !grid {
                let paragraph = NSMutableParagraphStyle()
                paragraph.lineBreakMode = .byTruncatingTail
                paragraph.alignment = rightToLeft ? .right : .left
                let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: ink, .paragraphStyle: paragraph]
                let rect = CGRect(x: rightToLeft ? inset : textInset, y: (size.height - textHeight) / 2, width: max(0, size.width - textInset - inset), height: textHeight)
                (tab.displayTitle as NSString).draw(in: rect, withAttributes: attributes)
            }
            return true
        }
    }

    final class DropView: NSView {
        var layout: TabDropLayout?
        var onMove: (CGPoint?) -> TabPlace? = { _ in nil }
        var onDrop: () -> Bool = { false }
        var makePreviews: () -> (NSImage, NSImage)? = { nil }
        private var previews: (NSImage, NSImage)?
        private var grid: Bool?

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? {
            layout?.draggedTabID != nil ? super.hitTest(point) : nil
        }

        override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
            previews = makePreviews()
            grid = nil
            return draggingUpdated(sender)
        }

        override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
            guard layout?.draggedTabID != nil, let previews else { return [] }
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
            layout?.draggedTabID = nil
            previews = nil
            grid = nil
        }

        override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { layout?.draggedTabID != nil }

        override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            _ = onMove(convert(sender.draggingLocation, from: nil))
            let accepted = onDrop()
            previews = nil
            grid = nil
            return accepted
        }
    }
}
