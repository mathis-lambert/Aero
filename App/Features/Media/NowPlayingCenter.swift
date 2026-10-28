import AppKit
import BrowserWebKit
import MediaPlayer
import Observation

/// The system's Now Playing and the media keys (docs/MEDIA.md › The system's Now Playing): Control Center and the
/// keyboard's play, next and previous keys show and drive the media that began playing last in any tab. Made the first
/// time a page plays; with nothing left to play it gives the keys back to the other apps.
@MainActor
final class NowPlayingCenter {
    /// What the system shows, as the browser has it; the artwork counts once it has loaded.
    private struct Item: Equatable, Sendable {
        let tabID: UUID
        let title: String
        let artist: String?
        let album: String?
        let artwork: URL?
        let artworkLoaded: Bool
        let isPlaying: Bool
        let actions: Set<PageMediaAction>
        let position: PlaybackPosition?
    }

    private let commands = MPRemoteCommandCenter.shared()
    private let info = MPNowPlayingInfoCenter.default()
    private weak var browser: BrowserModel?
    private var item: Item?
    private var observing: Task<Void, Never>?
    private var targets: [(MPRemoteCommand, Any)] = []

    init(browser: BrowserModel) {
        self.browser = browser
        register()
        observing = Task { [weak self, weak browser] in
            let items = Observations { @MainActor in browser.flatMap(Self.item(of:)) }
            for await item in items { self?.show(item) }
        }
    }

    isolated deinit {
        observing?.cancel()
        for (command, target) in targets { command.removeTarget(target) }
        info.nowPlayingInfo = nil
        info.playbackState = .stopped
    }

    private static func item(of browser: BrowserModel) -> Item? {
        guard let latest = browser.latestMedia else { return nil }
        let media = latest.media
        return Item(tabID: latest.tab.id, title: media.title ?? latest.tab.displayTitle, artist: media.artist ?? latest.tab.url.siteName,
                    album: media.album, artwork: media.artwork, artworkLoaded: media.artwork.map { browser.activities.artworks[$0] != nil } ?? false,
                    isPlaying: media.isPlaying, actions: media.actions, position: media.position)
    }

    private func show(_ item: Item?) {
        guard item != self.item else { return }
        self.item = item
        guard let item else {
            // Nothing to play: the keys go back to the other apps.
            info.nowPlayingInfo = nil
            info.playbackState = .stopped
            return
        }
        var properties: [String: Any] = [MPMediaItemPropertyTitle: item.title, MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue]
        if let artist = item.artist { properties[MPMediaItemPropertyArtist] = artist }
        if let album = item.album { properties[MPMediaItemPropertyAlbumTitle] = album }
        if let position = item.position {
            properties[MPMediaItemPropertyPlaybackDuration] = position.duration
            properties[MPNowPlayingInfoPropertyElapsedPlaybackTime] = position.elapsed(at: .now)
            properties[MPNowPlayingInfoPropertyPlaybackRate] = item.isPlaying ? position.rate : 0
        }
        if let url = item.artwork, let image = browser?.activities.artworks[url]?.image,
           let picture = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            properties[MPMediaItemPropertyArtwork] = Self.artwork(picture, size: image.size)
        }
        info.nowPlayingInfo = properties
        info.playbackState = item.isPlaying ? .playing : .paused
        commands.nextTrackCommand.isEnabled = item.actions.contains(.nextTrack)
        commands.previousTrackCommand.isEnabled = item.actions.contains(.previousTrack)
        commands.skipForwardCommand.isEnabled = !item.actions.contains(.nextTrack)
        commands.skipBackwardCommand.isEnabled = !item.actions.contains(.previousTrack)
    }

    /// The system promises no thread for a command: the handler runs anywhere and hands the action to the main actor.
    nonisolated private static func handler(_ action: @escaping @MainActor @Sendable () -> Void) -> (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
        { _ in
            Task { @MainActor in action() }
            return .success
        }
    }

    /// The system asks for the artwork on a queue of its own: the request runs off the main actor, on an immutable image.
    nonisolated private static func artwork(_ picture: CGImage, size: CGSize) -> MPMediaItemArtwork {
        MPMediaItemArtwork(boundsSize: size) { requested in NSImage(cgImage: picture, size: requested) }
    }

    /// Each command acts on the item shown when it comes.
    private func register() {
        commands.skipForwardCommand.preferredIntervals = [10]
        commands.skipBackwardCommand.preferredIntervals = [10]
        commands.changePlaybackPositionCommand.isEnabled = false
        let actions: [(MPRemoteCommand, (BrowserModel, UUID) -> Void)] = [
            (commands.togglePlayPauseCommand, { $0.toggleMedia(on: $1) }),
            (commands.playCommand, { $0.performMedia(.play, on: $1) }),
            (commands.pauseCommand, { $0.performMedia(.pause, on: $1) }),
            (commands.nextTrackCommand, { $0.performMedia(.nextTrack, on: $1) }),
            (commands.previousTrackCommand, { $0.performMedia(.previousTrack, on: $1) }),
            (commands.skipForwardCommand, { $0.performMedia(.seekForward, on: $1) }),
            (commands.skipBackwardCommand, { $0.performMedia(.seekBackward, on: $1) }),
        ]
        for (command, perform) in actions {
            command.isEnabled = true
            let target = command.addTarget(handler: Self.handler { [weak self] in
                guard let self, let browser = self.browser, let item = self.item else { return }
                perform(browser, item.tabID)
            })
            targets.append((command, target))
        }
    }
}
