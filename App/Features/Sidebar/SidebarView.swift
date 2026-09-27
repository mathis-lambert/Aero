import BrowserCore
import SwiftUI

/// Navigation and the address on top, one page of tabs per space, and a footer with the downloads
/// and the spaces. See docs/SPACES.md.
struct SidebarView: View {
    private static let footerHeight: CGFloat = 44

    let browser: BrowserModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                NativeWindowControls().frame(width: BrowserDesign.windowControlsWidth)
                navigation
            }
            .frame(height: BrowserDesign.sidebarHeaderHeight)

            AddressBar(browser: browser)
                .padding(.horizontal, BrowserDesign.rowInset)
                .padding(.top, 8)
                .padding(.bottom, 4)

            SpacePager(browser: browser)
            footer
        }
        .disabled(!browser.isReady || browser.isChangingStructure)
    }

    private var footer: some View {
        HStack(spacing: 0) {
            DownloadsButton(downloads: browser.downloads, presented: Bindable(browser.window).downloadsPresented, shortcut: browser.shortcuts.shortcut(for: .showDownloads)) { browser.perform(.showDownloads) }
            Spacer(minLength: 4)
            SpaceBar(browser: browser)
            Spacer(minLength: 4)
            IconButton(symbol: "plus", label: "New space", size: BrowserDesign.navigationButtonSize) {
                browser.present(.space(nil))
            }
            .accessibilityIdentifier("sidebar.addSpace")
        }
        .padding(.horizontal, BrowserDesign.rowInset)
        .frame(height: Self.footerHeight)
    }

    private var navigation: some View {
        HStack(spacing: 0) {
            IconButton(symbol: "sidebar.left", label: "Toggle sidebar", size: BrowserDesign.navigationButtonSize, shortcut: browser.shortcuts.shortcut(for: .toggleSidebar)) { browser.perform(.toggleSidebar) }
                .accessibilityIdentifier("sidebar.toggle")
            IconButton(symbol: "chevron.left", label: "Back", size: BrowserDesign.navigationButtonSize, shortcut: browser.shortcuts.shortcut(for: .back)) { browser.perform(.back) }
                .disabled(!browser.isEnabled(.back))
                .accessibilityIdentifier("sidebar.back")
            IconButton(symbol: "chevron.right", label: "Forward", size: BrowserDesign.navigationButtonSize, shortcut: browser.shortcuts.shortcut(for: .forward)) { browser.perform(.forward) }
                .disabled(!browser.isEnabled(.forward))
                .accessibilityIdentifier("sidebar.forward")
            IconButton(symbol: browser.currentPage?.isLoading == true ? "xmark" : "arrow.clockwise", label: browser.currentPage?.isLoading == true ? "Stop loading" : "Reload page", size: BrowserDesign.navigationButtonSize,
                       shortcut: browser.shortcuts.shortcut(for: browser.currentPage?.isLoading == true ? .stopLoading : .reload)) {
                browser.perform(browser.currentPage?.isLoading == true ? .stopLoading : .reload)
            }
            .disabled(browser.currentPage == nil)
            .contextMenu {
                ForEach([BrowserCommand.clearCookies, .clearCache, .siteSettings], id: \.self) { command in
                    Button(command.title) { browser.perform(command) }.disabled(!browser.isEnabled(command))
                }
            }
            .popover(isPresented: Bindable(browser.window).siteSettingsPresented, arrowEdge: .bottom) {
                if let site = browser.currentSite { SiteSettingsView(browser: browser, site: site) }
            }
            .accessibilityIdentifier("sidebar.reload")
        }
    }
}
