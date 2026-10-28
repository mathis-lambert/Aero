import BrowserCore
import SwiftUI

/// The frequent sites as tiles, and the tabs closed last as pills, under the New Tab page's bar. They
/// rise in after the gust's light reaches the bar, one after the other.
struct NewTabShelfView: View {
    private static let rowSpacing: CGFloat = 24
    private static let tileSpacing: CGFloat = 8
    private static let pillSpacing: CGFloat = 6
    /// Between two items rising in.
    private static let stagger: TimeInterval = 0.04
    private static let rise = Animation.spring(duration: 0.5, bounce: 0.18)

    let browser: BrowserModel
    let shelf: NewTabShelf
    /// Becomes true as the bar lights up: the shelf follows it.
    let revealed: Bool
    @Environment(\.browserReduceMotion) private var reduceMotion

    var body: some View {
        let sites = shelf.sites
        VStack(spacing: Self.rowSpacing) {
            if !sites.isEmpty {
                CenteredFlow(spacing: Self.tileSpacing, lineSpacing: Self.tileSpacing * 2) {
                    ForEach(Array(sites.enumerated()), id: \.element.key) { index, site in
                        SiteTile(browser: browser, shelf: shelf, site: site, focused: shelf.focus == .site(index))
                            .modifier(Rise(revealed: revealed, delay: Double(index) * Self.stagger))
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Frequent sites")
            }
            if !shelf.closed.isEmpty {
                CenteredFlow(spacing: Self.pillSpacing, lineSpacing: Self.pillSpacing) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(BrowserDesign.Typography.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.trailing, 2)
                        .accessibilityHidden(true)
                    ForEach(Array(shelf.closed.enumerated()), id: \.element.id) { index, tab in
                        ClosedTabPill(browser: browser, shelf: shelf, tab: tab, focused: shelf.focus == .closed(index))
                    }
                }
                .modifier(Rise(revealed: revealed, delay: Double(sites.count) * Self.stagger))
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Recently closed")
            }
        }
        .animation(reduceMotion ? nil : BrowserDesign.motion, value: sites.map(\.key))
        .frame(maxWidth: ControlBarView.width)
        .padding(.horizontal, ControlBarView.margin)
    }

    /// Its views in rows as wide as it is, each row centered: in a narrow page or pane, the rest goes to the next row
    /// rather than widening the page.
    private struct CenteredFlow: Layout {
        let spacing: CGFloat
        let lineSpacing: CGFloat

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
            let rows = rows(of: subviews, width: proposal.width ?? .infinity)
            let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
            return CGSize(width: rows.map(\.width).max() ?? 0, height: height)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
            var y = bounds.minY
            for row in rows(of: subviews, width: bounds.width) {
                var x = bounds.minX + (bounds.width - row.width) / 2
                for (index, size) in row.items {
                    subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                    x += size.width + spacing
                }
                y += row.height + lineSpacing
            }
        }

        private struct Row {
            var items: [(index: Int, size: CGSize)] = []
            var width: CGFloat = 0
            var height: CGFloat = 0
        }

        /// Each view at its own size, no wider than a row, on the row it fits.
        private func rows(of subviews: Subviews, width: CGFloat) -> [Row] {
            var rows: [Row] = [], row = Row()
            for index in subviews.indices {
                var size = subviews[index].sizeThatFits(.unspecified)
                if size.width > width { size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil)) }
                if !row.items.isEmpty, row.width + spacing + size.width > width {
                    rows.append(row)
                    row = Row()
                }
                row.width += (row.items.isEmpty ? 0 : spacing) + size.width
                row.height = max(row.height, size.height)
                row.items.append((index, size))
            }
            if !row.items.isEmpty { rows.append(row) }
            return rows
        }
    }

    private struct Rise: ViewModifier {
        let revealed: Bool
        let delay: TimeInterval
        @Environment(\.browserReduceMotion) private var reduceMotion

        func body(content: Content) -> some View {
            content
                .opacity(revealed ? 1 : 0)
                .offset(y: revealed ? 0 : 10)
                .scaleEffect(revealed ? 1 : 0.96, anchor: .top)
                .animation(reduceMotion ? nil : NewTabShelfView.rise.delay(delay), value: revealed)
        }
    }
}

/// A site's favicon on a card tinted by its color, and its name: it lifts under the pointer and the
/// arrow keys ring it in the space's light.
private struct SiteTile: View {
    private static let width: CGFloat = 84
    private static let minimumWidth: CGFloat = 60
    private static let card: CGFloat = 56
    private static let cardRadius: CGFloat = 16
    private static let icon: CGFloat = 28
    private static let initialFont = Font.system(size: 22, weight: .semibold, design: .rounded)

    let browser: BrowserModel
    let shelf: NewTabShelf
    let site: FrequentSites.Site
    let focused: Bool

    var body: some View {
        let name = site.url.siteName
        Button { shelf.open(site) } label: { EmptyView() }
            .buttonStyle(TileStyle(browser: browser, site: site, name: name, focused: focused))
            .frame(minWidth: Self.minimumWidth, idealWidth: Self.width, maxWidth: Self.width)
            .tooltip(site.title.isEmpty ? name : site.title)
            .iconContextMenu {
                Button("Hide from New Tab", systemImage: "eye.slash") { shelf.hide(site) }
            }
            .accessibilityLabel(Text(verbatim: name))
            .accessibilityValue(Text(verbatim: site.title))
            .accessibilityAddTraits(focused ? .isSelected : [])
            .accessibilityIdentifier("newTab.site")
    }

    /// Draws the whole tile, so that it follows the press.
    private struct TileStyle: ButtonStyle {
        let browser: BrowserModel
        let site: FrequentSites.Site
        let name: String
        let focused: Bool

        func makeBody(configuration: Configuration) -> some View {
            Face(browser: browser, site: site, name: name, focused: focused, pressed: configuration.isPressed)
        }
    }

    private struct Face: View {
        let browser: BrowserModel
        let site: FrequentSites.Site
        let name: String
        let focused: Bool
        let pressed: Bool
        @State private var hovered = false
        @Environment(\.palette) private var palette
        @Environment(\.browserReduceMotion) private var reduceMotion

        var body: some View {
            let key = browser.profile.flatMap { FaviconKey(profileID: $0.id, url: site.url) }
            let iconColor = key.flatMap { browser.favicons.favicon(for: $0).color }
            let lifted = hovered || focused
            VStack(spacing: 8) {
                FaviconView(cache: browser.favicons, key: key, size: SiteTile.icon, fetchingMissing: site.url) {
                    Text(verbatim: String(name.prefix(1)).uppercased())
                        .font(SiteTile.initialFont)
                        .foregroundStyle(browser.accent.light(in: palette.scheme))
                }
                .frame(width: SiteTile.card, height: SiteTile.card)
                .browserGlass(.control, tint: iconColor.map { Color(nsColor: $0) } ?? browser.accent.tint, radius: SiteTile.cardRadius)
                .overlay {
                    if focused {
                        RoundedRectangle(cornerRadius: SiteTile.cardRadius + 3, style: .continuous)
                            .strokeBorder(browser.accent.light(in: palette.scheme), lineWidth: 2)
                            .padding(-3)
                    }
                }
                .shadow(color: .black.opacity(lifted ? 0.14 : 0.05), radius: lifted ? 12 : 3, y: lifted ? 6 : 1)
                .scaleEffect(pressed ? 0.94 : lifted ? 1.05 : 1)
                .offset(y: lifted && !pressed ? -2 : 0)
                // The whole host when it fits, else its registrable domain, as Safari shortens addresses.
                ViewThatFits(in: .horizontal) {
                    Text(verbatim: name)
                    if let domain = browser.passwords.suffixes?.registrableDomain(of: name), domain != name {
                        Text(verbatim: domain)
                    }
                    Text(verbatim: name).truncationMode(.middle)
                }
                .font(BrowserDesign.Typography.caption.weight(.medium))
                .foregroundStyle(lifted ? palette.ink : palette.secondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
            .animation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.3), value: lifted)
            .animation(reduceMotion ? nil : .spring(duration: 0.18, bounce: 0), value: pressed)
        }
    }
}

/// A tab closed in this space, reopened where it was.
private struct ClosedTabPill: View {
    private static let height: CGFloat = 28
    private static let maximumTitleWidth: CGFloat = 150

    let browser: BrowserModel
    let shelf: NewTabShelf
    let tab: BrowserTab
    let focused: Bool
    @State private var hovered = false
    @Environment(\.palette) private var palette
    @Environment(\.browserReduceMotion) private var reduceMotion

    var body: some View {
        Button { shelf.reopen(tab) } label: {
            HStack(spacing: 6) {
                FaviconView(cache: browser.favicons, key: browser.faviconKey(for: tab), size: 14) {
                    Image(systemName: "globe").font(BrowserDesign.Typography.caption).foregroundStyle(.secondary)
                }
                Text(verbatim: tab.displayTitle)
                    .font(BrowserDesign.Typography.label)
                    .foregroundStyle(hovered || focused ? palette.ink : palette.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: Self.maximumTitleWidth, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .frame(height: Self.height)
            // Under the pointer it brightens behind its title, on the glass.
            .background { if hovered { Capsule().fill(palette.hover) } }
            .browserGlass(.control, radius: Self.height / 2)
            .overlay {
                if focused { Capsule().strokeBorder(browser.accent.light(in: palette.scheme), lineWidth: 2).padding(-2) }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : BrowserDesign.hover, value: hovered)
        .tooltip(tab.url.siteName)
        .accessibilityLabel(Text("Reopen \(tab.displayTitle)"))
        .accessibilityAddTraits(focused ? .isSelected : [])
        .accessibilityIdentifier("newTab.closed")
    }
}
