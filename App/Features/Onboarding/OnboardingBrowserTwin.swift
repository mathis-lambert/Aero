import BrowserCore
import SwiftUI

/// The browser itself in miniature: the main window drawn at the chrome's own sizes, from the browser's own records
/// (the selected space, its favorites and groups, the spaces in the footer), then scaled to the stage. Nothing in it
/// acts; what the person tries in the onboarding is shown here. See docs/ONBOARDING.md › Presentation.
struct OnboardingBrowserTwin: View {
    /// A compact browser window, in points.
    nonisolated static let size = CGSize(width: 780, height: 520)
    /// The favorites' rows below the space's name, where imported favorites land.
    nonisolated static let favoritesArea = CGRect(x: 2 * BrowserDesign.rowInset, y: BrowserDesign.sidebarHeaderHeight + 48 + 40, width: 180, height: 180)
    private static let pageRadius = BrowserDesign.Radius.page
    private static let footerHeight: CGFloat = 44
    /// Two rows of tiles, as a narrow sidebar shows them.
    private static let tileLimit = 6

    let browser: BrowserModel
    let onboarding: OnboardingModel
    var sidebarShown = true
    var controlBarShown = false
    /// Changes each time the recent-tab shortcut is tried.
    var recentTabTries = 0
    @State private var showsRecentTabs = false
    @Environment(\.palette) private var palette
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let space = browser.space
        HStack(spacing: 0) {
            if sidebarShown, let space {
                sidebar(space)
                    .frame(width: BrowserDesign.sidebarWidth)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            page(space)
                .padding(BrowserDesign.pageInset)
                .overlay(alignment: .topLeading) {
                    // Hidden sidebar: the window controls float over the page, as in the browser.
                    if !sidebarShown { TwinWindowControls().frame(width: BrowserDesign.windowControlsWidth, height: BrowserDesign.sidebarHeaderHeight) }
                }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(palette.sidebar)
        .clipShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.window, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: BrowserDesign.Radius.window, style: .continuous).strokeBorder(palette.line))
        .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.16), radius: 40, y: 28)
        .foregroundStyle(palette.ink)
        .tint(space?.color.tint ?? .accentColor)
        .allowsHitTesting(false)
        .browserAnimation(value: sidebarShown)
        .browserAnimation(value: controlBarShown)
        .browserAnimation(value: showsRecentTabs)
        .browserAnimation(value: space?.id)
        .browserAnimation(value: browser.session.tabs.count)
        .task(id: recentTabTries) {
            guard recentTabTries > 0 else { return }
            showsRecentTabs = true
            try? await Task.sleep(for: .seconds(1.4))
            showsRecentTabs = false
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("onboarding.preview")
    }

    // MARK: - Sidebar

    private func sidebar(_ space: BrowserSpace) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                TwinWindowControls().frame(width: BrowserDesign.windowControlsWidth)
                ForEach(["sidebar.left", "chevron.left", "chevron.right", "arrow.clockwise"], id: \.self) { symbol in
                    Image(systemName: symbol)
                        .font(BrowserDesign.Typography.chrome.weight(.medium))
                        .foregroundStyle(symbol == "sidebar.left" ? palette.ink : palette.secondary.opacity(0.6))
                        .frame(width: BrowserDesign.navigationButtonSize, height: BrowserDesign.navigationButtonSize)
                }
            }
            .frame(height: BrowserDesign.sidebarHeaderHeight)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(BrowserDesign.Typography.label).foregroundStyle(palette.secondary)
                Text("Search or enter an address").foregroundStyle(palette.secondary).lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(BrowserDesign.Typography.chrome)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(palette.fill, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
            .padding(.horizontal, BrowserDesign.rowInset)
            .padding(.top, 8)
            .padding(.bottom, 4)

            spacePage(space)
                .id(space.id)
                .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 24)), removal: .opacity.combined(with: .offset(x: -24))))
                .frame(maxHeight: .infinity, alignment: .top)
                .clipped()
                // The list runs on below the window's edge, as a scrolled sidebar would.
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.82), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))

            HStack(spacing: 0) {
                Image(systemName: "arrow.down.circle").foregroundStyle(palette.secondary)
                    .frame(width: BrowserDesign.navigationButtonSize, height: BrowserDesign.navigationButtonSize)
                Spacer(minLength: 4)
                HStack(spacing: 2) {
                    ForEach(browser.session.spaces) { item in
                        SpaceIcon(space: item, size: 13)
                            .opacity(item.id == space.id ? 1 : 0.5)
                            .frame(width: 24, height: 24)
                            .background(item.id == space.id ? palette.fill : .clear, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "plus").foregroundStyle(palette.secondary)
                    .frame(width: BrowserDesign.navigationButtonSize, height: BrowserDesign.navigationButtonSize)
            }
            .font(BrowserDesign.Typography.chrome.weight(.medium))
            .padding(.horizontal, BrowserDesign.rowInset)
            .frame(height: Self.footerHeight)
        }
    }

    /// The space's favorites in the sidebar's own order: tiles, groups, loose rows, the line, then New Tab.
    private func spacePage(_ space: BrowserSpace) -> some View {
        let tabs = SidebarTabs(session: browser.session, space: space, drop: nil)
        return VStack(alignment: .leading, spacing: SidebarTabs.rowSpacing) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 8) {
                    SpaceIcon(space: space, size: 13)
                    Text(verbatim: space.name).font(.headline).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(verbatim: browser.session.profiles.first { $0.id == space.profileID }?.name ?? "")
                    .font(.caption).foregroundStyle(palette.secondary).lineLimit(1)
            }
            .padding(.horizontal, BrowserDesign.rowInset)
            .padding(.bottom, 8)

            if !tabs.grid.isEmpty {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: FavoritesGrid.spacing), count: 3), spacing: FavoritesGrid.spacing) {
                    ForEach(tabs.grid.prefix(Self.tileLimit)) { tile($0) }
                }
                .padding(.bottom, FavoritesGrid.spacing)
            }
            ForEach(tabs.groups, id: \.group.id) { group, _ in
                HStack(spacing: BrowserDesign.rowInset) {
                    Image(systemName: "folder").font(BrowserDesign.Typography.label).foregroundStyle(palette.secondary)
                        .frame(width: BrowserDesign.rowIconWidth)
                    Text(verbatim: group.name).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(BrowserDesign.Typography.glyph).foregroundStyle(palette.secondary)
                }
                .padding(.horizontal, BrowserDesign.rowInset)
                .frame(height: BrowserDesign.tabRowHeight)
                .transition(.opacity.combined(with: .offset(x: -12)))
            }
            ForEach(Array(tabs.loose.enumerated()), id: \.element.id) { index, tab in
                row(tab)
                    // Imported rows land one after another, as their icons arrive.
                    .transition(.asymmetric(insertion: .offset(x: -16).combined(with: .opacity)
                        .animation(.spring(duration: 0.45, bounce: 0.18).delay(onboarding.step == .importing ? 0.75 + Double(index) * 0.06 : 0)),
                                            removal: .opacity))
            }
            Hairline().padding(.vertical, 6).padding(.horizontal, BrowserDesign.rowInset)
            HStack(spacing: BrowserDesign.rowInset) {
                Image(systemName: "plus").frame(width: BrowserDesign.rowIconWidth)
                Text("New tab")
                Spacer(minLength: 0)
            }
            .padding(.horizontal, BrowserDesign.rowInset)
            .frame(height: BrowserDesign.tabRowHeight)
            .background(palette.raised, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
        }
        .font(BrowserDesign.Typography.chrome)
        .padding(.horizontal, BrowserDesign.rowInset)
        .padding(.top, 12)
    }

    private func tile(_ tab: BrowserTab) -> some View {
        favicon(tab, size: BrowserDesign.pinnedIconSize, initial: .system(size: 18, weight: .medium, design: .rounded))
            .frame(maxWidth: .infinity)
            .frame(height: FavoritesGrid.tileHeight)
            .browserSurface(fill: palette.favoriteTile, border: palette.line, radius: BrowserDesign.Radius.card)
            .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    private func row(_ tab: BrowserTab) -> some View {
        HStack(spacing: BrowserDesign.rowInset) {
            favicon(tab, size: BrowserDesign.tabIconSize, initial: .system(size: 11, weight: .semibold, design: .rounded))
                .frame(width: BrowserDesign.rowIconWidth)
            Text(verbatim: tab.displayTitle).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, BrowserDesign.rowInset)
        .frame(height: BrowserDesign.tabRowHeight)
    }

    /// The favorite's own icon, which an import brings along, or its site's initial.
    private func favicon(_ tab: BrowserTab, size: CGFloat, initial: Font) -> some View {
        FaviconView(cache: browser.favicons, key: browser.faviconKey(for: tab), size: size) {
            Text(verbatim: String(tab.url.siteName.prefix(1)).uppercased()).font(initial).foregroundStyle(palette.secondary)
        }
    }

    // MARK: - Page

    /// The New Tab page: the space's wind rising toward the control bar, as the browser opens on it.
    private func page(_ space: BrowserSpace?) -> some View {
        let accent = space?.color ?? .initial
        let colors = NewTabView.windColors(for: accent, in: scheme)
        return GeometryReader { proxy in
            let size = proxy.size
            let barTop = size.height * 0.4
            let barCenter = CGPoint(x: size.width / 2, y: barTop + ControlBarView.fieldHeight / 2)
            ZStack(alignment: .top) {
                palette.canvas
                // Rises again in each space, in its color.
                WindArc(ink: colors.ink, core: colors.core, light: colors.light, size: size, target: barCenter, activity: 0)
                    .id(space?.id)
                    .transition(.opacity)
                controlBar(accent: accent, delay: WindArc.arrival(at: barCenter, in: size))
                    .frame(width: min(520, size.width - 96))
                    .padding(.top, barTop)
                if showsRecentTabs { recentTabs(accent: accent).frame(maxWidth: .infinity, maxHeight: .infinity) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.pageRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Self.pageRadius, style: .continuous).strokeBorder(palette.line.opacity(0.6)))
    }

    private func controlBar(accent: SpaceColor, delay: TimeInterval) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: BrowserDesign.rowInset) {
                Image(systemName: "magnifyingglass").font(BrowserDesign.Typography.field).foregroundStyle(palette.secondary)
                Text(controlBarShown ? "Search, enter an address, or find a command" : "Search or enter an address")
                    .font(BrowserDesign.Typography.field).foregroundStyle(palette.secondary).lineLimit(1)
                Spacer(minLength: 0)
                if controlBarShown { Keycaps(.cancelAction).transition(.opacity) }
            }
            .padding(.horizontal, 16)
            .frame(height: ControlBarView.fieldHeight)
            if controlBarShown {
                Hairline()
                VStack(spacing: 2) {
                    ForEach(Array([BrowserCommand.newTab, .newSpace, .showHistory, .toggleSidebar].enumerated()), id: \.offset) { index, command in
                        HStack(spacing: BrowserDesign.rowInset) {
                            Image(systemName: command.symbol).foregroundStyle(palette.secondary).frame(width: BrowserDesign.rowIconWidth)
                            Text(verbatim: command.title).lineLimit(1)
                            Spacer(minLength: 8)
                            if let shortcut = browser.shortcuts.shortcut(for: command) { Keycaps(shortcut) }
                        }
                        .font(BrowserDesign.Typography.chrome)
                        .padding(.horizontal, BrowserDesign.rowInset)
                        .frame(height: BrowserDesign.tabRowHeight)
                        .background(index == 0 ? palette.fill : .clear, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
                    }
                }
                .padding(8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(palette.raised)
        .clipShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.card))
        .controlBarGlow(accent: accent.light(in: scheme), cornerRadius: BrowserDesign.Radius.card, delay: delay)
        .panelShadow()
    }

    /// The recent-tab switcher, as Control-Tab shows it over the page.
    private func recentTabs(accent: SpaceColor) -> some View {
        let tabs = Array(browser.tabs.prefix(4))
        return HStack(spacing: 8) {
            if tabs.isEmpty {
                Text("New tab").font(BrowserDesign.Typography.chrome).foregroundStyle(palette.secondary).padding(.horizontal, 24).frame(height: 88)
            }
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                VStack(alignment: .leading, spacing: 8) {
                    RoundedRectangle(cornerRadius: BrowserDesign.Radius.control).fill(palette.canvas).frame(height: 64)
                        .overlay { favicon(tab, size: 24, initial: .system(size: 18, weight: .medium, design: .rounded)) }
                    Text(verbatim: tab.displayTitle).font(BrowserDesign.Typography.caption).lineLimit(1)
                }
                .padding(8)
                .frame(width: 112)
                .background(index == min(1, tabs.count - 1) ? accent.tint.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.card))
                .overlay {
                    if index == min(1, tabs.count - 1) { RoundedRectangle(cornerRadius: BrowserDesign.Radius.card).strokeBorder(accent.tint.opacity(0.6), lineWidth: 1.5) }
                }
            }
        }
        .padding(10)
        .background(palette.raised, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.card + 4))
        .overlay(RoundedRectangle(cornerRadius: BrowserDesign.Radius.card + 4).strokeBorder(palette.line))
        .panelShadow()
        .transition(.scale(scale: 0.94).combined(with: .opacity))
    }
}

/// The window's close, minimize and zoom buttons as a picture, at the positions the real group takes in the header.
private struct TwinWindowControls: View {
    private static let colors: [Color] = [Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.78, blue: 0.25)]

    var body: some View {
        ZStack(alignment: .leading) {
            ForEach(0..<3, id: \.self) { index in
                Circle().fill(Self.colors[index])
                    .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
                    .frame(width: 12, height: 12)
                    .offset(x: 20 + CGFloat(index) * 23)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }
}
