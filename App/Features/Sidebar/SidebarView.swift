import BrowserCore
import SwiftUI

/// Navigation and the address on top, one page of tabs per profile, and a footer with the downloads
/// and the profiles. See docs/PROFILES.md.
struct SidebarView: View {
    private static let footerHeight: CGFloat = 44

    let browser: BrowserModel
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                NativeWindowControls().frame(width: BrowserDesign.windowControlsWidth)
                navigation
            }
            .frame(height: BrowserDesign.sidebarHeaderHeight)

            Button { browser.perform(.openLocation) } label: {
                HStack(spacing: 8) {
                    Image(systemName: browser.internalPage?.symbol ?? (browser.selectedTab == nil ? "magnifyingglass" : "globe"))
                        .font(BrowserDesign.Typography.label)
                        .foregroundStyle(.secondary)
                    if let page = browser.internalPage {
                        Text(verbatim: page.title).lineLimit(1)
                    } else if let tab = browser.selectedTab {
                        Text(verbatim: tab.url.siteName)
                            .lineLimit(1).truncationMode(.middle)
                    } else {
                        Text("Search or enter an address")
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .font(BrowserDesign.Typography.chrome)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(palette.fill, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
                .contentShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
            }
            .buttonStyle(QuietButtonStyle())
            .accessibilityLabel("Open location")
            .accessibilityIdentifier("sidebar.location")
            .padding(.horizontal, BrowserDesign.rowInset)
            .padding(.top, 8)
            .padding(.bottom, 4)

            ProfilePager(browser: browser)
            footer
        }
        .disabled(!browser.isReady)
    }

    private var footer: some View {
        HStack(spacing: 0) {
            DownloadsButton(downloads: browser.downloads)
            Spacer(minLength: 4)
            ProfileBar(browser: browser)
            Spacer(minLength: 4)
            IconButton(symbol: "plus", label: "New profile", size: BrowserDesign.navigationButtonSize) {
                browser.window.profileSheet = .create
            }
            .accessibilityIdentifier("sidebar.addProfile")
        }
        .padding(.horizontal, BrowserDesign.rowInset)
        .frame(height: Self.footerHeight)
    }

    private var navigation: some View {
        HStack(spacing: 0) {
            IconButton(symbol: "sidebar.left", label: "Toggle sidebar", size: BrowserDesign.navigationButtonSize, shortcut: BrowserCommand.toggleSidebar.shortcut) { browser.perform(.toggleSidebar) }
                .accessibilityIdentifier("sidebar.toggle")
            IconButton(symbol: "chevron.left", label: "Back", size: BrowserDesign.navigationButtonSize, shortcut: BrowserCommand.back.shortcut) { browser.perform(.back) }
                .disabled(!browser.isEnabled(.back))
                .accessibilityIdentifier("sidebar.back")
            IconButton(symbol: "chevron.right", label: "Forward", size: BrowserDesign.navigationButtonSize, shortcut: BrowserCommand.forward.shortcut) { browser.perform(.forward) }
                .disabled(!browser.isEnabled(.forward))
                .accessibilityIdentifier("sidebar.forward")
            IconButton(symbol: browser.currentPage?.isLoading == true ? "xmark" : "arrow.clockwise", label: browser.currentPage?.isLoading == true ? "Stop loading" : "Reload page", size: BrowserDesign.navigationButtonSize,
                       shortcut: browser.currentPage?.isLoading == true ? nil : BrowserCommand.reload.shortcut) {
                if browser.currentPage?.isLoading == true { browser.currentPage?.stop() }
                else { browser.perform(.reload) }
            }
            .disabled(browser.currentPage == nil)
            .accessibilityIdentifier("sidebar.reload")
        }
    }
}
