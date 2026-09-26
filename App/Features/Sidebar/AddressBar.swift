import BrowserCore
import SwiftUI

/// The selected tab's address, which opens the control bar, and on a website its Copy link and
/// control center buttons. See docs/SITE_CONTROLS.md › Address actions.
struct AddressBar: View {
    private static let height: CGFloat = 36
    private static let buttonSize: CGFloat = 28
    /// More pinned extensions stay in the control center, so the address keeps its room.
    private static let pinnedLimit = 2
    private static let copiedDuration = Duration.milliseconds(1500)

    let browser: BrowserModel
    @State private var showsCopied = false
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 0) {
            Button { browser.perform(.openLocation) } label: {
                HStack(spacing: 8) {
                    // A website is named by its address alone; browser pages and the empty field keep their symbol.
                    if let symbol = browser.internalPage?.symbol ?? (browser.selectedTab == nil ? "magnifyingglass" : nil) {
                        Image(systemName: symbol)
                            .font(BrowserDesign.Typography.label)
                            .foregroundStyle(.secondary)
                    }
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
                .padding(.horizontal, 12)
                .frame(maxHeight: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
            }
            .buttonStyle(QuietButtonStyle())
            .accessibilityLabel("Open location")
            .accessibilityIdentifier("sidebar.location")
            if browser.currentSite != nil {
                HStack(spacing: 0) {
                    if let profileID = browser.window.selectedProfileID, let extensions = browser.pages.extensionsIfMade(for: profileID) {
                        ForEach(browser.installedExtensions(inProfile: profileID).filter { $0.isEnabled && $0.isPinned }.prefix(Self.pinnedLimit)) { record in
                            ExtensionButton(browser: browser, extensions: extensions, record: record, size: Self.buttonSize, anchorsPopup: true)
                        }
                    }
                    IconButton(symbol: showsCopied ? "checkmark" : BrowserCommand.copyLink.symbol, label: showsCopied ? "Link copied" : "Copy link",
                               size: Self.buttonSize, shortcut: BrowserCommand.copyLink.shortcut) { browser.perform(.copyLink) }
                        .contentTransition(.symbolEffect(.replace))
                        .accessibilityIdentifier("address.copyLink")
                    IconButton(symbol: BrowserCommand.controlCenter.symbol, label: "Site controls", size: Self.buttonSize) {
                        browser.window.controlCenterPresented.toggle()
                    }
                    .background(AnchorView(key: ExtensionAnchor.controlCenter, anchors: browser.window.extensionAnchors))
                    .popover(isPresented: Bindable(browser.window).controlCenterPresented, arrowEdge: .bottom) {
                        if let site = browser.currentSite { ControlCenterView(browser: browser, site: site) }
                    }
                    .accessibilityIdentifier("address.controlCenter")
                }
                .padding(.trailing, 4)
                .transition(.opacity)
            }
        }
        .font(BrowserDesign.Typography.chrome)
        .frame(height: Self.height)
        .background(palette.fill, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
        .task(id: browser.window.linkCopies) {
            guard browser.window.linkCopies > 0 else { return }
            showsCopied = true
            do { try await Task.sleep(for: Self.copiedDuration) } catch { return }
            showsCopied = false
        }
    }
}
