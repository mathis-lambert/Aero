import BrowserCore
import SwiftUI

/// A frozen recent-tab list. Highlighting an item never loads or resizes its page.
struct TabCycleView: View {
    let browser: BrowserModel
    let cycle: RecentTabCycle
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(cycle.tabs, id: \.self) { id in
                        if let tab = browser.tabs.first(where: { $0.id == id }) {
                            Button {
                                browser.selectTab(id)
                            } label: {
                                HStack(spacing: 12) {
                                    FaviconView(cache: browser.favicons, key: browser.faviconKey(for: tab), size: 24) {
                                        Image(systemName: InternalPage(url: tab.url)?.symbol ?? "globe")
                                    }
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(verbatim: tab.displayTitle).font(BrowserDesign.Typography.chrome).lineLimit(1)
                                        Text(verbatim: tab.url.host() ?? tab.url.absoluteString)
                                            .font(BrowserDesign.Typography.caption).foregroundStyle(palette.secondary).lineLimit(1)
                                    }
                                    Spacer(minLength: 0)
                                    Image(systemName: "return").foregroundStyle(palette.secondary)
                                        .opacity(id == cycle.selected ? 1 : 0).accessibilityHidden(true)
                                }
                                .frame(minHeight: 32)
                                .padding(10)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(id == cycle.selected ? browser.accent.tint.opacity(0.16) : .clear,
                                            in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
                            }
                            .buttonStyle(QuietButtonStyle())
                            .accessibilityAddTraits(id == cycle.selected ? .isSelected : [])
                            .accessibilityIdentifier("tabCycle.item")
                            .id(id)
                        }
                    }
                }
                .padding(8)
            }
            .frame(width: 360, height: min(CGFloat(cycle.tabs.count) * 56 + 12, 348))
            .browserGlass(.panel, radius: BrowserDesign.Radius.card)
            .panelShadow()
            .onAppear { scroll.scrollTo(cycle.selected, anchor: .center) }
            .onChange(of: cycle.selected) { _, id in scroll.scrollTo(id, anchor: .center) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Recent Tabs"))
        .accessibilityHint(Text("Switch between recently used tabs. Release the modifiers to choose."))
        .accessibilityIdentifier("tabCycle")
    }
}
