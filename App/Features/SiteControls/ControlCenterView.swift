import AppKit
import BrowserCore
import SecurityInterface
import SwiftUI

/// The site's controls, in a popover on the address: sharing, extensions, blocking and picture in
/// picture, its security, and its data. See docs/SITE_CONTROLS.md › Control center.
struct ControlCenterView: View {
    private static let tileHeight: CGFloat = 44
    private static let switchIconSize: CGFloat = 30

    let browser: BrowserModel
    let site: BrowserModel.CurrentSite
    @State private var showsSiteSettings = false
    @Environment(\.palette) private var palette

    var body: some View {
        if showsSiteSettings {
            SiteSettingsView(browser: browser, site: site) { showsSiteSettings = false }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                if let url = browser.currentAddress {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: Self.tileHeight)
                            .background(palette.fill, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.card))
                            .contentShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.card))
                    }
                    .buttonStyle(QuietButtonStyle(radius: BrowserDesign.Radius.card))
                    .accessibilityIdentifier("controlCenter.share")
                }
                section("Extensions") { ExtensionsGrid(browser: browser) }
                section("Settings") {
                    VStack(alignment: .leading, spacing: 4) {
                        siteSwitch(.ads, title: "Block ads & trackers", identifier: "controlCenter.ads")
                        siteSwitch(.automaticPictureInPicture, title: "Automatic picture in picture", identifier: "controlCenter.pictureInPicture")
                    }
                }
                Divider()
                HStack {
                    security
                    Spacer()
                    moreMenu
                }
            }
            .padding(16)
            .frame(width: SiteSettingsView.width)
        }
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(BrowserDesign.Typography.label).foregroundStyle(.secondary)
            content()
        }
    }

    private func siteSwitch(_ permission: SitePermission, title: LocalizedStringKey, identifier: String) -> some View {
        let isOn = browser.isOn(permission, at: site)
        return Button { browser.toggle(permission, at: site) } label: {
            HStack(spacing: 10) {
                Image(systemName: permission.symbol)
                    .font(BrowserDesign.Typography.label)
                    .foregroundStyle(isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    .frame(width: Self.switchIconSize, height: Self.switchIconSize)
                    .background(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(palette.fill), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).lineLimit(1)
                    Text(isOn ? "On" : "Off").font(BrowserDesign.Typography.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(4)
            .contentShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
        }
        .buttonStyle(QuietButtonStyle())
        .browserAnimation(value: isOn)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(isOn ? "On" : "Off"))
        .accessibilityIdentifier(identifier)
    }

    /// A secure page opens its certificate; a page that is not has none worth showing.
    @ViewBuilder private var security: some View {
        if browser.currentPage?.isSecure == true {
            Button(action: showCertificate) { securityLabel("Secure", symbol: "lock.fill") }
                .buttonStyle(QuietButtonStyle())
                .tooltip(String(localized: "Show certificate"))
                .accessibilityIdentifier("controlCenter.security")
        } else {
            securityLabel("Not secure", symbol: "lock.open")
                .foregroundStyle(.secondary)
                .tooltip(String(localized: "This page, or something it loaded, is not encrypted"))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("controlCenter.security")
        }
    }

    private func securityLabel(_ title: LocalizedStringKey, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(BrowserDesign.Typography.label)
            .padding(.horizontal, 8)
            .frame(height: BrowserDesign.navigationButtonSize)
            .contentShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
    }

    private var moreMenu: some View {
        Menu {
            Button(BrowserCommand.clearCache.title) { browser.perform(.clearCache) }
            Button(BrowserCommand.clearCookies.title) { browser.perform(.clearCookies) }
            Divider()
            Button(BrowserCommand.siteSettings.title) { showsSiteSettings = true }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: BrowserDesign.navigationButtonSize, height: BrowserDesign.navigationButtonSize)
        }
        .menuStyle(.button)
        .buttonStyle(QuietButtonStyle())
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More")
        .accessibilityIdentifier("controlCenter.more")
    }

    /// The system's certificate panel, as a sheet on the browser window once the popover is gone.
    private func showCertificate() {
        guard let trust = browser.currentPage?.serverTrust, let window = WindowConfiguration.mainWindow else { return }
        browser.window.controlCenterPresented = false
        SFCertificatePanel.shared().beginSheet(for: window, modalDelegate: nil, didEnd: nil, contextInfo: nil, trust: trust, showGroup: true)
    }
}
