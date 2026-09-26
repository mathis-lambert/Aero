import AppKit
import BrowserCore
import BrowserWebKit
import SwiftUI

extension BrowserModel {
    /// The selected page's site in its profile. See docs/SITE_CONTROLS.md.
    struct CurrentSite: Equatable {
        let host: String
        let origin: SiteOrigin
        let profileID: UUID
    }

    var currentSite: CurrentSite? {
        guard currentPage != nil, internalPage == nil, let tab = selectedTab, let host = tab.url.host(),
              let origin = SiteOrigin(url: tab.url), let profileID = profileID(of: tab) else { return nil }
        return CurrentSite(host: host, origin: origin, profileID: profileID)
    }

    /// The profile's decision for the site, or the browser-wide setting for ads and picture in
    /// picture; `nil` only for a device WebKit should ask for.
    func decision(for permission: SitePermission, at origin: SiteOrigin, profileID: UUID) -> SiteDecision? {
        session.profiles.first { $0.id == profileID }?.decision(for: permission, at: origin) ?? defaultDecision(for: permission)
    }

    func defaultDecision(for permission: SitePermission) -> SiteDecision? {
        switch permission {
        case .ads: preferences.blocksAds ? .block : .allow
        case .automaticPictureInPicture: preferences.automaticPictureInPicture ? .allow : .block
        case .camera, .microphone, .location: nil
        }
    }

    func isOn(_ permission: SitePermission, at site: CurrentSite) -> Bool {
        decision(for: permission, at: site.origin, profileID: site.profileID) == (permission == .ads ? .block : .allow)
    }

    /// A site switched back to the browser-wide setting keeps no decision of its own.
    func toggle(_ permission: SitePermission, at site: CurrentSite) {
        let next: SiteDecision = decision(for: permission, at: site.origin, profileID: site.profileID) == .allow ? .block : .allow
        setDecision(next == defaultDecision(for: permission) ? nil : next, for: permission, at: site)
    }

    func setBlocksAds(_ blocks: Bool) {
        preferences.blocksAds = blocks
        pages.refreshContentBlocking()
    }

    /// Removing cookies or all data reloads the page, so it stops using what was removed.
    func clearSiteData(_ kind: SiteDataKind) async {
        guard let site = currentSite else { return }
        let page = currentPage
        await pages.removeSiteData(kind, for: site.host, profileID: site.profileID)
        if kind != .cache { page?.reload() }
    }

    /// The page's live address, which may be ahead of the saved one after `pushState`.
    var currentAddress: URL? {
        (currentPage?.webView.url ?? selectedTab?.url).flatMap { NavigationInput.isWebURL($0) ? $0 : nil }
    }

    func copyLink() {
        guard let url = currentAddress else { return }
        let item = NSPasteboardItem()
        item.setString(url.absoluteString, forType: .URL)
        item.setString(url.absoluteString, forType: .string)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([item])
        window.linkCopies += 1
        AccessibilityNotification.Announcement(String(localized: "Link copied")).post()
    }
}

extension SitePermission {
    var title: LocalizedStringKey {
        switch self {
        case .camera: "Camera"
        case .microphone: "Microphone"
        case .location: "Location"
        case .ads: "Ads and trackers"
        case .automaticPictureInPicture: "Automatic picture in picture"
        }
    }

    var symbol: String {
        switch self {
        case .camera: "video"
        case .microphone: "mic"
        case .location: "location"
        case .ads: "shield"
        case .automaticPictureInPicture: "pip"
        }
    }
}
