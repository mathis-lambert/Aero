import AppKit
import BrowserCore
import SwiftUI

/// Favorites as tiles of their favicon, a split's as its panes' icons stacked. A dragged tab takes a slot as a gap, and
/// the tiles after it move aside; an empty grid exposes a tinted target only during a drag. The tile metrics here also
/// draw the drag image and the onboarding's sidebar.
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
    let entries: [SidebarTabs.Entry]
    let selectedTabID: UUID?
    let marked: Set<UUID>
    let lifted: Set<UUID>
    /// Tabs are being dragged, so an empty grid shows where they can go.
    let dragging: Bool
    let layout: TabDropLayout

    var body: some View {
        if entries.isEmpty {
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
                ForEach(entries) { tile($0) }
            }
            .padding(.bottom, Self.spacing)
        }
    }

    private func tile(_ entry: SidebarTabs.Entry) -> some View {
        FavoriteTile(browser: browser, entry: entry, selected: entry.tabs.contains { selectedTabID == $0.id || marked.contains($0.id) },
                     isLifted: lifted.contains(entry.id))
            .dropFrame(.tab(entry.id), in: layout)
    }
}

/// One favorite, or a split of favorites. It owns its hover, so the pointer crossing the grid redraws only the tiles it
/// enters and leaves. A favorite away from its pinned page wears a badge on its corner that takes it back, as a double
/// click does.
private struct FavoriteTile: View {
    let browser: BrowserModel
    let entry: SidebarTabs.Entry
    let selected: Bool
    let isLifted: Bool
    @State private var hovered = false
    @Environment(\.browserReduceMotion) private var reduceMotion

    /// The tab that stands for the tile: the favorite, or the split's first pane.
    private var tab: BrowserTab { entry.tabs[0] }

    var body: some View {
        Button { browser.click(tab, modifiers: NSEvent.modifierFlags) } label: {
            Group {
                switch entry {
                case .tab(let tab): FavoriteIcon(browser: browser, tab: tab)
                case .split(_, let panes): SplitStack(browser: browser, panes: panes)
                }
            }
            .opacity(isLifted ? 0 : 1)
            .frame(maxWidth: .infinity)
            .frame(height: FavoritesGrid.tileHeight)
            .modifier(TileSurface(state: isLifted ? .lifted : selected ? .active(glow: glowColor) : hovered ? .hovered : .resting))
            .contentShape(RoundedRectangle(cornerRadius: FavoritesGrid.radius))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if !isLifted, case .tab(let tab) = entry, tab.hasLeftPinnedPage {
                PinnedPageReturn(browser: browser, tab: tab, style: .badge)
                    .padding(3)
                    .transition(.opacity)
            }
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            if case .tab(let tab) = entry { browser.returnToPinnedPage(tab.id) }
        })
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : BrowserDesign.hover, value: hovered)
        .tooltip(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .iconContextMenu {
            switch entry {
            case .tab(let tab): TabContextMenu(browser: browser, tab: tab)
            case .split(let split, let panes): SplitContextMenu(browser: browser, split: split, panes: panes)
            }
        }
        .popover(isPresented: renaming, arrowEdge: .bottom) {
            Group {
                if browser.window.renaming == .pinnedPage(tab.id) { PinnedPageField(browser: browser, tab: tab) }
                else { RenameField(name: tab.displayTitle) { browser.renameTab(tab.id, to: $0) } end: { browser.window.endRenaming(.tab(tab.id)) } }
            }
            .frame(width: 240)
            .padding(10)
        }
        .tabDraggable(tab, browser: browser)
        .accessibilityIdentifier(entry.tabs.count > 1 ? "sidebar.splitTile" : "sidebar.tile")
    }

    private var title: String {
        entry.tabs.map(\.shownTitle).formatted(.list(type: .and))
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

    /// A tile has no title to edit in place, so its name, or its pinned page, is edited in a popover.
    private var renaming: Binding<Bool> {
        Binding { [.tab(tab.id), .pinnedPage(tab.id)].contains(browser.window.renaming) } set: { shown in
            if !shown, let target = browser.window.renaming { browser.window.endRenaming(target) }
        }
    }
}

/// A favorite's icon, its site's initial or a browser page's symbol until it has one.
private struct FavoriteIcon: View {
    let browser: BrowserModel
    let tab: BrowserTab
    var size = FavoritesGrid.iconSize

    var body: some View {
        let placeholder = size * FavoritesGrid.placeholderSize / FavoritesGrid.iconSize
        FaviconView(cache: browser.favicons, key: browser.faviconKey(for: tab), size: size, fetchingMissing: tab.url) {
            if let page = InternalPage(url: tab.url) {
                Image(systemName: page.symbol).font(.system(size: placeholder)).foregroundStyle(.secondary)
            } else {
                Text(verbatim: String(tab.url.siteName.prefix(1)).uppercased()).font(.system(size: placeholder, weight: .medium, design: .rounded))
            }
        }
    }
}

/// A split's panes as small squares stacked one over the next, in reading order, the first on top.
struct SplitStack: View {
    static let side: CGFloat = 22
    static let overlap: CGFloat = 9
    static let radius: CGFloat = 6
    static let iconSize: CGFloat = 13

    let browser: BrowserModel
    let panes: [BrowserTab]
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: -Self.overlap) {
            ForEach(Array(panes.enumerated()), id: \.element.id) { index, tab in
                FavoriteIcon(browser: browser, tab: tab, size: Self.iconSize)
                    .frame(width: Self.side, height: Self.side)
                    .background(palette.raised, in: RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: Self.radius, style: .continuous).strokeBorder(palette.line) }
                    .shadow(color: .black.opacity(0.12), radius: 1.5, x: 1)
                    .zIndex(Double(panes.count - index))
            }
        }
    }
}

/// A tile's surface: clear glass at rest, brighter under the pointer, and a tinted lens when active, its icon's color
/// glowing through it. A dragged tile leaves a plain gap.
private struct TileSurface: ViewModifier {
    enum State {
        case resting, hovered, active(glow: Color), lifted
    }

    let state: State
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        switch state {
        // Under the pointer, the same glass with a veil under it: glass coming and going at each pass would flicker.
        case .resting, .hovered:
            let veil = if case .hovered = state { palette.scheme == .dark ? 0.07 : 0.35 } else { 0.0 }
            content
                .background(Color.white.opacity(veil), in: RoundedRectangle(cornerRadius: FavoritesGrid.radius, style: .continuous))
                .browserGlass(.tile, radius: FavoritesGrid.radius)
        case .active(let glow):
            content
                .browserGlass(.selection, tint: glow, radius: FavoritesGrid.radius)
                .glassGlow(glow, radius: FavoritesGrid.radius)
        case .lifted: content.browserSurface(fill: palette.fill, border: .clear, radius: FavoritesGrid.radius)
        }
    }
}
