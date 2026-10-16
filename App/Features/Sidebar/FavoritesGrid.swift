import AppKit
import BrowserCore
import SwiftUI

/// Favorites as tiles of their favicon. A dragged tab takes a slot as a gap, and the tiles after it
/// move aside; an empty grid exposes a tinted target only during a drag.
struct FavoritesGrid: View {
    static let spacing: CGFloat = 8
    static let tileHeight: CGFloat = 44
    /// Three columns at the sidebar's minimum width; extra room adds columns.
    static let minimumTileWidth = floor((BrowserDesign.sidebarWidth - 2 * BrowserDesign.rowInset - 2 * spacing) / 3)

    static func columnCount(in width: CGFloat) -> Int {
        max(1, Int((width + spacing) / (minimumTileWidth + spacing)))
    }

    static func tileWidth(in width: CGFloat) -> CGFloat {
        let columns = columnCount(in: width)
        return (width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
    }
    /// The site initial, or a browser page's symbol, stands in for a missing favicon.
    private static let placeholderSize: CGFloat = 18
    private static let initialFont = Font.system(size: placeholderSize, weight: .medium, design: .rounded)

    let browser: BrowserModel
    let tabs: [BrowserTab]
    let selectedTabID: UUID?
    let lifted: UUID?
    let layout: TabDropLayout
    @State private var hoveredTabID: UUID?
    @Environment(\.browserReduceMotion) private var reduceMotion
    @Environment(\.palette) private var palette

    var body: some View {
        if tabs.isEmpty {
            if layout.draggedTabID != nil {
                RoundedRectangle(cornerRadius: BrowserDesign.Radius.card)
                    .strokeBorder(Color.accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .background(Color.accentColor.opacity(0.05), in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.card))
                    .overlay { Image(systemName: "plus").foregroundStyle(Color.accentColor) }
                    .frame(height: Self.tileHeight)
                    .accessibilityLabel("Favorites grid")
                    .accessibilityIdentifier("sidebar.emptyGrid")
                    .transition(.opacity)
            }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.minimumTileWidth), spacing: Self.spacing)], spacing: Self.spacing) {
                ForEach(tabs) { tile($0) }
            }
            .padding(.bottom, Self.spacing)
        }
    }

    private func tile(_ tab: BrowserTab) -> some View {
        let selected = selectedTabID == tab.id
        let isLifted = lifted == tab.id
        let isActive = selected && !isLifted
        let highlight = isActive ? selectionColors(for: tab) : (fill: palette.favoriteTileHover, border: palette.line)
        let fill = isLifted ? palette.fill : isActive ? highlight.fill : hoveredTabID == tab.id ? palette.favoriteTileHover : palette.favoriteTile
        return Button { browser.showTab(tab) } label: {
            FaviconView(cache: browser.favicons, key: browser.faviconKey(for: tab), size: BrowserDesign.pinnedIconSize, fetchingMissing: tab.url) {
                if let page = InternalPage(url: tab.url) {
                    Image(systemName: page.symbol).font(.system(size: Self.placeholderSize)).foregroundStyle(.secondary)
                } else {
                    Text(verbatim: String(tab.url.siteName.prefix(1)).uppercased()).font(Self.initialFont)
                }
            }
            .opacity(isLifted ? 0 : 1)
            .frame(maxWidth: .infinity)
            .frame(height: Self.tileHeight)
            .browserSurface(fill: fill, border: isLifted ? .clear : highlight.border,
                            radius: BrowserDesign.Radius.card, borderWidth: isActive ? 1.5 : 1)
            .shadow(color: isActive ? highlight.border.opacity(0.24) : .clear, radius: 4, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.card))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { hoveredTabID = tab.id }
            else if hoveredTabID == tab.id { hoveredTabID = nil }
        }
        .animation(reduceMotion ? nil : BrowserDesign.hover, value: hoveredTabID == tab.id)
        .tooltip(tab.displayTitle)
        .accessibilityLabel(tab.displayTitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu { TabContextMenu(browser: browser, tab: tab) }
        .popover(isPresented: renaming(tab), arrowEdge: .bottom) {
            RenameField(name: tab.displayTitle) { browser.renameTab(tab.id, to: $0) } end: { browser.window.endRenaming(.tab(tab.id)) }
                .frame(width: 200)
                .padding(10)
        }
        .tabDraggable(tab, in: layout)
        .accessibilityIdentifier("sidebar.tile")
        .dropFrame(.tab(tab.id), in: layout)
    }

    /// Keep the hover surface's HSL lightness; only its hue and subtle saturation change.
    private func selectionColors(for tab: BrowserTab) -> (fill: Color, border: Color) {
        let iconColor = browser.faviconKey(for: tab).flatMap { browser.favicons.favicon(for: $0).color }
        let tint = iconColor ?? NSColor(browser.accent.tint)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        (tint.usingColorSpace(.sRGB) ?? tint).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        let lightness = palette.favoriteHighlightLightness
        let s = min(Double(saturation) * 0.4, 0.35)
        let value = lightness + s * min(lightness, 1 - lightness)
        let fill = Color(hue: Double(hue), saturation: 2 * (1 - lightness / value), brightness: value)
        let border = Color(hue: Double(hue), saturation: min(Double(saturation), 0.8),
                           brightness: palette.scheme == .dark ? 0.85 : 0.65)
        return (fill, border)
    }

    /// A tile has no title to edit in place, so its name is edited in a popover.
    private func renaming(_ tab: BrowserTab) -> Binding<Bool> {
        Binding { browser.window.renaming == .tab(tab.id) } set: { if !$0 { browser.window.endRenaming(.tab(tab.id)) } }
    }
}
