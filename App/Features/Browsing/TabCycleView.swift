import BrowserCore
import SwiftUI

/// A frozen recent-tab strip. Highlighting a card never loads or resizes its page.
struct TabCycleView: View {
    private static let cardWidth: CGFloat = 200
    private static let pictureSize = CGSize(width: 184, height: 116)
    let browser: BrowserModel
    let cycle: RecentTabCycle
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { area in
            let naturalWidth = CGFloat(cycle.tabs.count) * Self.cardWidth + CGFloat(max(0, cycle.tabs.count - 1)) * 8 + 24
            ScrollViewReader { scroll in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 8) {
                        ForEach(cycle.tabs, id: \.self) { id in
                            if let tab = browser.tabs.first(where: { $0.id == id }) {
                                card(tab)
                                    .id(id)
                            }
                        }
                    }
                    .padding(12)
                }
                .scrollIndicators(.hidden)
                .frame(width: min(naturalWidth, 1064, max(0, area.size.width - 64)), height: 180)
                .browserGlass(.panel, radius: BrowserDesign.Radius.card + 4)
                .panelShadow()
                .onAppear { scroll.scrollTo(cycle.selected, anchor: .center) }
                .onChange(of: cycle.selected) { _, id in scroll.scrollTo(id, anchor: .center) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Recent Tabs"))
        .accessibilityHint(Text("Switch between recently used tabs. Release the modifiers to choose."))
        .accessibilityIdentifier("tabCycle")
    }

    private func card(_ tab: BrowserTab) -> some View {
        let selected = tab.id == cycle.selected
        return Button { browser.selectTab(tab.id) } label: {
            VStack(alignment: .leading, spacing: 8) {
                thumbnail(tab)
                    .frame(width: Self.pictureSize.width, height: Self.pictureSize.height)
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
                    .accessibilityHidden(true)
                HStack(spacing: 6) {
                    favicon(tab, size: 16)
                    Text(verbatim: tab.displayTitle)
                        .font(BrowserDesign.Typography.chrome)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 16)
            }
            .frame(width: Self.pictureSize.width)
            .padding(8)
            .background(selected ? palette.hover : .clear, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.card))
            .overlay {
                RoundedRectangle(cornerRadius: BrowserDesign.Radius.card)
                    .strokeBorder(selected ? browser.accent.tint.opacity(0.65) : .clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(QuietButtonStyle(radius: BrowserDesign.Radius.card))
        .accessibilityLabel(Text(verbatim: tab.displayTitle))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("tabCycle.item")
    }

    @ViewBuilder private func thumbnail(_ tab: BrowserTab) -> some View {
        if let image = browser.tabPreviews.image(for: tab.id, at: tab.url) {
            Image(decorative: image, scale: 1).resizable().scaledToFill()
        } else {
            palette.canvas.overlay { favicon(tab, size: 32) }
        }
    }

    private func favicon(_ tab: BrowserTab, size: CGFloat) -> some View {
        FaviconView(cache: browser.favicons, key: browser.faviconKey(for: tab), size: size) {
            Image(systemName: InternalPage(url: tab.url)?.symbol ?? "globe")
                .font(.system(size: size * 0.8)).foregroundStyle(palette.secondary)
        }
    }
}
