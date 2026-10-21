import AppKit
import BrowserCore
import SwiftUI

/// Favorites as tiles of their favicon. A dragged tab takes a slot as a gap, and the tiles after it
/// move aside; an empty grid exposes a tinted target only during a drag. The tile metrics here also draw the drag
/// image and the onboarding's sidebar.
struct FavoritesGrid: View {
    static let spacing: CGFloat = 6
    static let tileHeight: CGFloat = 38
    static let iconSize: CGFloat = 18
    static let radius: CGFloat = 10
    /// Three columns at the sidebar's minimum width; extra room adds columns.
    static let minimumTileWidth = floor((BrowserDesign.sidebarWidth - 2 * BrowserDesign.sidebarInset - 2 * spacing) / 3)

    static func columnCount(in width: CGFloat) -> Int {
        max(1, Int((width + spacing) / (minimumTileWidth + spacing)))
    }

    static func tileWidth(in width: CGFloat) -> CGFloat {
        let columns = columnCount(in: width)
        return (width - CGFloat(columns - 1) * spacing) / CGFloat(columns)
    }
    /// The site initial, or a browser page's symbol, stands in for a missing favicon.
    static let placeholderSize: CGFloat = 15
    static let initialFont = Font.system(size: placeholderSize, weight: .medium, design: .rounded)

    let browser: BrowserModel
    let tabs: [BrowserTab]
    let selectedTabID: UUID?
    let marked: Set<UUID>
    let lifted: Set<UUID>
    /// Tabs are being dragged, so an empty grid shows where they can go.
    let dragging: Bool
    let layout: TabDropLayout

    var body: some View {
        if tabs.isEmpty {
            if dragging {
                RoundedRectangle(cornerRadius: Self.radius)
                    .strokeBorder(Color.accentColor.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .background(Color.accentColor.opacity(0.05), in: RoundedRectangle(cornerRadius: Self.radius))
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
        FavoriteTile(browser: browser, tab: tab, selected: selectedTabID == tab.id || marked.contains(tab.id),
                     isLifted: lifted.contains(tab.id))
            .dropFrame(.tab(tab.id), in: layout)
    }
}

/// One favorite. It owns its hover, so the pointer crossing the grid redraws only the tiles it enters and leaves.
private struct FavoriteTile: View {
    let browser: BrowserModel
    let tab: BrowserTab
    let selected: Bool
    let isLifted: Bool
    @State private var hovered = false
    @Environment(\.browserReduceMotion) private var reduceMotion

    var body: some View {
        Button { browser.click(tab, modifiers: NSEvent.modifierFlags) } label: {
            FaviconView(cache: browser.favicons, key: browser.faviconKey(for: tab), size: FavoritesGrid.iconSize, fetchingMissing: tab.url) {
                if let page = InternalPage(url: tab.url) {
                    Image(systemName: page.symbol).font(.system(size: FavoritesGrid.placeholderSize)).foregroundStyle(.secondary)
                } else {
                    Text(verbatim: String(tab.url.siteName.prefix(1)).uppercased()).font(FavoritesGrid.initialFont)
                }
            }
            .opacity(isLifted ? 0 : 1)
            .frame(maxWidth: .infinity)
            .frame(height: FavoritesGrid.tileHeight)
            .modifier(TileSurface(state: isLifted ? .lifted : selected ? .active(glow: glowColor) : hovered ? .hovered : .resting))
            .contentShape(RoundedRectangle(cornerRadius: FavoritesGrid.radius))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : BrowserDesign.hover, value: hovered)
        .tooltip(tab.displayTitle)
        .accessibilityLabel(tab.displayTitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu { TabContextMenu(browser: browser, tab: tab) }
        .popover(isPresented: renaming, arrowEdge: .bottom) {
            RenameField(name: tab.displayTitle) { browser.renameTab(tab.id, to: $0) } end: { browser.window.endRenaming(.tab(tab.id)) }
                .frame(width: 200)
                .padding(10)
        }
        .tabDraggable(tab, browser: browser)
        .accessibilityIdentifier("sidebar.tile")
    }

    /// The favicon's color, or the space's, made vivid enough to glow: a dull or dark icon still lights its glass.
    private var glowColor: Color {
        let iconColor = browser.faviconKey(for: tab).flatMap { browser.favicons.favicon(for: $0).color }
        let tint = iconColor ?? NSColor(browser.accent.tint)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
        (tint.usingColorSpace(.sRGB) ?? tint).getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
        // A grey icon glows grey, faintly, rather than taking a hue it does not have.
        return Color(hue: Double(hue), saturation: min(Double(saturation), 0.85), brightness: max(Double(brightness), 0.75))
    }

    /// A tile has no title to edit in place, so its name is edited in a popover.
    private var renaming: Binding<Bool> {
        Binding { browser.window.renaming == .tab(tab.id) } set: { if !$0 { browser.window.endRenaming(.tab(tab.id)) } }
    }
}

/// A tile's surface: recessed at rest, brighter under the pointer, and a tinted lens when active, its icon's color
/// glowing through it. Hovering adds no glass, which would come and go over the icon at each pass of the pointer. A
/// dragged tile leaves a plain gap.
private struct TileSurface: ViewModifier {
    enum State {
        case resting, hovered, active(glow: Color), lifted
    }

    let state: State
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        switch state {
        case .resting: content.browserSurface(fill: palette.favoriteTile, border: palette.line, radius: FavoritesGrid.radius)
        case .hovered: content.browserSurface(fill: palette.favoriteTileHover, border: palette.line, radius: FavoritesGrid.radius)
        case .active(let glow):
            content
                .browserGlass(.selection, tint: glow, radius: FavoritesGrid.radius)
                .glassGlow(glow, radius: FavoritesGrid.radius)
        case .lifted: content.browserSurface(fill: palette.fill, border: .clear, radius: FavoritesGrid.radius)
        }
    }
}
