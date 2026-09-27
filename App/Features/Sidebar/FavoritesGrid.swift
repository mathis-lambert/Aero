import BrowserCore
import SwiftUI

/// Favorites as tiles of their favicon. A dragged tab takes a slot as a gap, and the tiles after it
/// move aside; an empty grid exposes a tinted target only during a drag.
struct FavoritesGrid: View {
    static let spacing: CGFloat = 8
    static let columns = 3
    static let tileHeight: CGFloat = 60
    /// The site initial, or a browser page's symbol, stands in for a missing favicon.
    private static let placeholderSize: CGFloat = 18
    private static let initialFont = Font.system(size: placeholderSize, weight: .medium, design: .rounded)

    let browser: BrowserModel
    let tabs: [BrowserTab]
    let selectedTabID: UUID?
    let lifted: UUID?
    let layout: TabDropLayout
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
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Self.spacing), count: Self.columns), spacing: Self.spacing) {
                ForEach(tabs) { tile($0) }
            }
            .padding(.bottom, Self.spacing)
        }
    }

    private func tile(_ tab: BrowserTab) -> some View {
        let selected = selectedTabID == tab.id
        let isLifted = lifted == tab.id
        return Button { browser.showTab(tab) } label: {
            FaviconView(cache: browser.favicons, key: browser.faviconKey(for: tab), size: BrowserDesign.pinnedIconSize) {
                if let page = InternalPage(url: tab.url) {
                    Image(systemName: page.symbol).font(.system(size: Self.placeholderSize)).foregroundStyle(.secondary)
                } else {
                    Text(verbatim: String(tab.url.siteName.prefix(1)).uppercased()).font(Self.initialFont)
                }
            }
            .opacity(isLifted ? 0 : 1)
            .frame(maxWidth: .infinity)
            .frame(height: Self.tileHeight)
            .browserSurface(fill: isLifted ? palette.fill : palette.raised,
                            border: isLifted ? .clear : selected ? Color.accentColor : palette.line,
                            radius: BrowserDesign.Radius.card)
            .contentShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.card))
        }
        .buttonStyle(QuietButtonStyle(radius: BrowserDesign.Radius.card))
        .tooltip(tab.displayTitle)
        .accessibilityLabel(tab.displayTitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .contextMenu { TabContextMenu(browser: browser, tab: tab) }
        .popover(isPresented: renaming(tab), arrowEdge: .bottom) {
            RenameField(name: tab.displayTitle) { browser.renameTab(tab.id, to: $0) } end: { browser.window.endRenaming(.tab(tab.id)) }
                .frame(width: 200)
                .padding(10)
        }
        .tabDraggable(tab)
        .accessibilityIdentifier("sidebar.tile")
        .dropFrame(.tab(tab.id), in: layout)
    }

    /// A tile has no title to edit in place, so its name is edited in a popover.
    private func renaming(_ tab: BrowserTab) -> Binding<Bool> {
        Binding { browser.window.renaming == .tab(tab.id) } set: { if !$0 { browser.window.endRenaming(.tab(tab.id)) } }
    }
}
