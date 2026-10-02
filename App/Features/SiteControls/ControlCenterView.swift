import AppKit
import BrowserCore
import SecurityInterface
import SwiftUI

/// The site's controls, in a popover on the address: sharing, extensions, blocking and picture in
/// picture, its security, and its data. See docs/SITE_CONTROLS.md › Control center.
struct ControlCenterView: View {
    private static let tileHeight: CGFloat = 44

    let browser: BrowserModel
    let site: BrowserModel.CurrentSite
    @State private var showsSiteSettings = false
    @Environment(\.palette) private var palette

    var body: some View {
        if showsSiteSettings {
            SiteSettingsView(browser: browser, site: site) { showsSiteSettings = false }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
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
                    Button { browser.perform(.capturePortrait) } label: {
                        Image(systemName: BrowserCommand.capturePortrait.symbol)
                            .frame(width: Self.tileHeight, height: Self.tileHeight)
                            .background(palette.fill, in: RoundedRectangle(cornerRadius: BrowserDesign.Radius.card))
                            .contentShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.card))
                    }
                    .buttonStyle(QuietButtonStyle(radius: BrowserDesign.Radius.card))
                    .disabled(!browser.isEnabled(.capturePortrait))
                    .tooltip(BrowserCommand.capturePortrait.title)
                    .accessibilityLabel(BrowserCommand.capturePortrait.title)
                    .accessibilityIdentifier("controlCenter.portrait")
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
        Toggle(title, isOn: Binding(get: { browser.isOn(permission, at: site) }, set: { _ in browser.toggle(permission, at: site) }))
            .toggleStyle(ControlCenterToggleStyle(symbol: permission.symbol))
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

/// A switch of the control center, drawn like the system's: a round symbol filled while on.
private struct ControlCenterToggleStyle: ToggleStyle {
    private static let iconSize: CGFloat = 30
    let symbol: String
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        Button { configuration.isOn.toggle() } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(BrowserDesign.Typography.label)
                    .foregroundStyle(configuration.isOn ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                    .frame(width: Self.iconSize, height: Self.iconSize)
                    .background(configuration.isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(palette.fill), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    configuration.label.lineLimit(1)
                    Text(configuration.isOn ? "On" : "Off").font(BrowserDesign.Typography.caption).foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Spacer(minLength: 0)
            }
            .padding(4)
            .contentShape(RoundedRectangle(cornerRadius: BrowserDesign.Radius.control))
        }
        .buttonStyle(QuietButtonStyle())
        .browserAnimation(value: configuration.isOn)
    }
}
