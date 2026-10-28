import AppKit
import BrowserCore
import BrowserWebKit
import Foundation
import Observation

/// What the window's pages play and record, by tab (docs/MEDIA.md). The page registry reports each change; a page
/// closed or hibernated reports itself idle, so nothing outlives its page.
@MainActor @Observable
final class PageActivities {
    private(set) var byTab: [UUID: PageActivity] = [:]
    /// The player the person closed, until its media begins playing again.
    var dismissed: (tabID: UUID, startedAt: Date?)?

    func update(_ tabID: UUID, _ activity: PageActivity) {
        byTab[tabID] = activity.isIdle ? nil : activity
    }

    // MARK: Artwork

    /// An artwork and the color it glows with.
    struct Artwork {
        let image: NSImage
        let color: NSColor?
    }

    private static let maximumArtworkBytes = 4 << 20
    private static let keptArtworks = 12
    /// Artwork is fetched as icons are: without cookies or credentials, so it reveals no profile.
    @ObservationIgnored private let session = URLSession.anonymous(requestTimeout: 10, resourceTimeout: 20)
    private(set) var artworks: [URL: Artwork] = [:]
    @ObservationIgnored private var artworkOrder: [URL] = []
    /// Asked for already, fetched or not: an artwork that fails is not fetched again at every redraw.
    @ObservationIgnored private var requested: Set<URL> = []

    /// The artwork at `url`, fetched the first time it is asked for; the last few are kept.
    func artwork(at url: URL) -> Artwork? {
        if let artwork = artworks[url] { return artwork }
        guard requested.insert(url).inserted else { return nil }
        Task { [weak self, session] in
            guard let (data, response) = try? await session.data(from: url), (response as? HTTPURLResponse)?.statusCode == 200,
                  data.count <= Self.maximumArtworkBytes, let image = NSImage(data: data) else { return }
            let color = await FaviconColor.extract(from: data).map { NSColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: 1) }
            self?.keep(Artwork(image: image, color: color), at: url)
        }
        return nil
    }

    private func keep(_ artwork: Artwork, at url: URL) {
        artworks[url] = artwork
        artworkOrder.append(url)
        while artworkOrder.count > Self.keptArtworks {
            let oldest = artworkOrder.removeFirst()
            artworks[oldest] = nil
            requested.remove(oldest)
        }
    }
}

/// The media the sidebar's player shows, and its tab.
struct NowPlaying: Equatable, Sendable {
    let tab: BrowserTab
    let media: PageMedia
}

extension BrowserModel {
    /// The tabs on screen: the selected tab and the other panes of its split. Their own page shows what they play.
    var shownTabIDs: Set<UUID> { Set(currentSplit?.tabIDs ?? window.selectedTabID.map { [$0] } ?? []) }

    /// The media of a tab off screen that began playing last, a playing one before a paused one, unless its player was
    /// closed since it began. Media that never played, such as a video waiting on its page, has no player.
    var nowPlaying: NowPlaying? {
        guard let latest = latestMedia(excluding: shownTabIDs) else { return nil }
        if let dismissed = activities.dismissed, dismissed.tabID == latest.tab.id, dismissed.startedAt == latest.media.startedAt { return nil }
        return latest
    }

    /// The media that began playing last in any tab, on screen or not, a playing one before a paused one: what the
    /// system's Now Playing and the media keys drive.
    var latestMedia: NowPlaying? { latestMedia(excluding: []) }

    private func latestMedia(excluding excluded: Set<UUID>) -> NowPlaying? {
        let candidates = activities.byTab.compactMap { id, activity -> NowPlaying? in
            guard !excluded.contains(id), let media = activity.media, media.startedAt != nil,
                  let tab = session.tabs.first(where: { $0.id == id }) else { return nil }
            return NowPlaying(tab: tab, media: media)
        }
        return candidates.max { ($0.media.isPlaying ? 1 : 0, $0.media.startedAt ?? .distantPast) < ($1.media.isPlaying ? 1 : 0, $1.media.startedAt ?? .distantPast) }
    }

    /// Tabs off screen using the camera or the microphone, which must never go unnoticed.
    var capturingTabs: [(tab: BrowserTab, activity: PageActivity)] {
        let shown = shownTabIDs
        return session.tabs.compactMap { tab in
            guard !shown.contains(tab.id), let activity = activities.byTab[tab.id], activity.isCapturing else { return nil }
            return (tab, activity)
        }
    }

    func activity(of tabID: UUID) -> PageActivity? { activities.byTab[tabID] }

    /// The media the media commands act on: the player's, else the selected tab's.
    var mediaTarget: NowPlaying? {
        if let nowPlaying { return nowPlaying }
        guard let tab = selectedTab, let media = activities.byTab[tab.id]?.media else { return nil }
        return NowPlaying(tab: tab, media: media)
    }

    func performMedia(_ action: PageMediaAction, on tabID: UUID) {
        pages.livePage(tabID)?.perform(action)
    }

    func toggleMedia(on tabID: UUID) {
        performMedia(activities.byTab[tabID]?.media?.isPlaying == true ? .pause : .play, on: tabID)
    }

    /// The next track when the site has one, else ten seconds on; and back likewise.
    func skipMedia(forward: Bool, on tabID: UUID) {
        let actions = activities.byTab[tabID]?.media?.actions ?? []
        if forward { performMedia(actions.contains(.nextTrack) ? .nextTrack : .seekForward, on: tabID) }
        else { performMedia(actions.contains(.previousTrack) ? .previousTrack : .seekBackward, on: tabID) }
    }

    func dismissPlayer() {
        guard let nowPlaying else { return }
        activities.dismissed = (nowPlaying.tab.id, nowPlaying.media.startedAt)
    }

    func setCaptureMuted(_ tabID: UUID, camera: Bool? = nil, microphone: Bool? = nil) {
        pages.livePage(tabID)?.setCaptureMuted(camera: camera, microphone: microphone)
    }
}
