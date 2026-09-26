import BrowserCore
import BrowserWebKit
import SwiftUI

/// The site's data and every permission, on the reload button or inside the control center.
struct SiteSettingsView: View {
    static let width: CGFloat = 340

    let browser: BrowserModel
    let site: BrowserModel.CurrentSite
    /// Shown inside the control center, which it returns to.
    var onBack: (() -> Void)?
    @State private var usage: SiteDataUsage?

    private var profile: BrowserProfile? { browser.session.profiles.first { $0.id == site.profileID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 6) {
                if let onBack {
                    IconButton(symbol: "chevron.left", label: "Back", size: 24, action: onBack)
                        .accessibilityIdentifier("siteSettings.back")
                }
                Text(verbatim: site.host)
                    .font(BrowserDesign.Typography.chrome.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            VStack(alignment: .leading, spacing: 8) {
                heading("Cookies and site data")
                if let usage {
                    Text(usage.cookies == 0 ? String(localized: "No cookies") : String(localized: "\(usage.cookies) cookies"))
                        .accessibilityIdentifier("siteSettings.cookies")
                    if usage.storesOtherData {
                        Text("Other site data is stored").font(BrowserDesign.Typography.caption).foregroundStyle(.secondary)
                    }
                }
                Button("Delete data") {
                    Task {
                        await browser.clearSiteData(.all)
                        usage = await browser.pages.siteDataUsage(for: site.host, profileID: site.profileID)
                    }
                }
                .buttonStyle(PanelButtonStyle())
                .accessibilityIdentifier("siteSettings.deleteData")
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    heading("Permissions")
                    Spacer()
                    if profile?.sitePermissions[site.origin] != nil {
                        Button { browser.resetPermissions(at: site) } label: {
                            Text("Reset permissions").font(BrowserDesign.Typography.caption).foregroundStyle(.secondary)
                                .padding(.horizontal, 6).padding(.vertical, 3)
                        }
                        .buttonStyle(QuietButtonStyle())
                        .accessibilityIdentifier("siteSettings.resetPermissions")
                    }
                }
                ForEach(SitePermission.allCases, id: \.self, content: row)
            }
        }
        .padding(16)
        .frame(width: Self.width)
        .task(id: site) { usage = await browser.pages.siteDataUsage(for: site.host, profileID: site.profileID) }
    }

    private func heading(_ text: LocalizedStringKey) -> some View {
        Text(text).font(BrowserDesign.Typography.label).foregroundStyle(.secondary)
    }

    private func row(_ permission: SitePermission) -> some View {
        HStack {
            Label(permission.title, systemImage: permission.symbol).lineLimit(1)
            Spacer(minLength: 8)
            Picker(permission.title, selection: Binding(
                get: { profile?.decision(for: permission, at: site.origin) },
                set: { browser.setDecision($0, for: permission, at: site) }
            )) {
                Text(permission.isDevice ? "Ask" : "Default").tag(SiteDecision?.none)
                Text("Allow").tag(SiteDecision?.some(.allow))
                Text("Block").tag(SiteDecision?.some(.block))
            }
            .labelsHidden()
            .fixedSize()
            .accessibilityIdentifier("siteSettings.\(permission.rawValue)")
        }
    }
}
