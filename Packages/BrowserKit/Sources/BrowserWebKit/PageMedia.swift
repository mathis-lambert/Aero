import BrowserCore
import Foundation
import WebKit

/// What a page plays and records, for the sidebar's player and the tabs' indicators (docs/MEDIA.md).
public struct PageActivity: Equatable, Sendable {
    public var media: PageMedia?
    public var camera = CaptureState.off
    public var microphone = CaptureState.off

    public init() {}

    public var isIdle: Bool { media == nil && camera == .off && microphone == .off }
    public var isCapturing: Bool { camera != .off || microphone != .off }
}

/// A camera or microphone a page uses: off, on, or kept by the page but muted.
public enum CaptureState: Sendable {
    case off, active, muted
}

/// The page's media: what its Media Session says it plays, else its media elements.
public struct PageMedia: Equatable, Sendable {
    public var isPlaying: Bool
    /// Heard, or named by the site's Media Session: a muted video playing behind a page is neither, and never counts as
    /// begun.
    public var isAudible: Bool
    public var title: String?
    public var artist: String?
    public var album: String?
    /// The largest artwork the site gives, a website address.
    public var artwork: URL?
    /// The actions the site's Media Session handles; play, pause and seeking always work on the media element.
    public var actions: Set<PageMediaAction>
    public var position: PlaybackPosition?
    /// When it last began playing to be heard: the most recent is the one the player shows.
    public var startedAt: Date?

    public init(isPlaying: Bool, isAudible: Bool = true, title: String? = nil, artist: String? = nil, album: String? = nil, artwork: URL? = nil,
                actions: Set<PageMediaAction> = [], position: PlaybackPosition? = nil, startedAt: Date? = nil) {
        self.isPlaying = isPlaying
        self.isAudible = isAudible
        self.title = title
        self.artist = artist
        self.album = album
        self.artwork = artwork
        self.actions = actions
        self.position = position
        self.startedAt = startedAt
    }
}

/// Where playback was at `date`, so the elapsed time can be drawn as it moves without asking the page again.
public struct PlaybackPosition: Equatable, Sendable {
    public let elapsed: Double
    public let duration: Double
    public let rate: Double
    public let date: Date

    public func elapsed(at now: Date) -> Double {
        min(duration, max(0, elapsed + now.timeIntervalSince(date) * rate))
    }
}

/// What the player asks of a page, by the Media Session's names.
public enum PageMediaAction: String, Sendable, CaseIterable {
    case play, pause
    case previousTrack = "previoustrack", nextTrack = "nexttrack"
    case seekBackward = "seekbackward", seekForward = "seekforward"
}

/// Two scripts tell what a page plays, in every frame, so a player embedded in an article counts. In the page's world, one keeps the handlers the site gives its Media Session and
/// relays its metadata, which the site sets there; an event carries them, and the actions the player asks, between the
/// worlds. In Aero's world, the other follows the page's media elements and reports to the app. Both are untrusted:
/// the page can send anything through the event, so the app bounds what it takes.
@MainActor
enum MediaScripts {
    static let handlerName = "aeroMedia"
    nonisolated static let maximumTextLength = 512
    nonisolated static let maximumAddressLength = 4096

    static let session = WKUserScript(source: """
        (() => {
            const session = navigator.mediaSession;
            if (!session || typeof MediaSession === "undefined") return;
            const proto = MediaSession.prototype;
            const handlers = new Map();
            let position = null;
            const text = (value) => typeof value === "string" ? value : null;
            const announce = () => {
                const metadata = session.metadata;
                const artwork = Array.from(metadata?.artwork ?? []).map((image) => ({ src: text(image.src), sizes: text(image.sizes) }));
                document.dispatchEvent(new CustomEvent("aero:media-session", { detail: JSON.stringify({
                    title: text(metadata?.title), artist: text(metadata?.artist), album: text(metadata?.album), artwork,
                    actions: [...handlers.keys()], state: text(session.playbackState), position
                }) }));
            };
            const setHandler = proto.setActionHandler;
            proto.setActionHandler = function (action, handler) {
                if (typeof handler === "function") handlers.set(action, handler); else handlers.delete(action);
                queueMicrotask(announce);
                return setHandler.call(this, action, handler);
            };
            const setPosition = proto.setPositionState;
            if (setPosition) proto.setPositionState = function (state) {
                position = state ? { duration: state.duration, elapsed: state.position ?? 0, rate: state.playbackRate ?? 1 } : null;
                queueMicrotask(announce);
                return setPosition.call(this, state);
            };
            for (const name of ["metadata", "playbackState"]) {
                const property = Object.getOwnPropertyDescriptor(proto, name);
                if (!property?.set) continue;
                Object.defineProperty(proto, name, { ...property, set(value) { property.set.call(this, value); queueMicrotask(announce); } });
            }
            document.addEventListener("aero:media-action", (event) => {
                const handler = handlers.get(event.detail);
                if (handler) try { handler({ action: event.detail }); } catch {}
            });
        })();
        """, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page)

    static let elements = WKUserScript(source: """
        (() => {
            // Names this document among the page's frames; a frame gone takes its media with it.
            const frame = crypto.randomUUID?.() ?? String(Math.random());
            let session = null, last = null, timer = 0, reported = false;
            const media = () => {
                const all = Array.from(document.querySelectorAll("audio, video"));
                return all.find((element) => !element.paused && !element.ended) ?? (last?.isConnected ? last : null) ?? null;
            };
            const report = () => {
                const element = media();
                const duration = element && Number.isFinite(element.duration) ? element.duration : null;
                reported = true;
                window.webkit.messageHandlers.\(handlerName).postMessage({
                    frame,
                    hasElement: element !== null,
                    playing: element ? !element.paused && !element.ended : false,
                    audible: element ? !element.muted && element.volume > 0 : false,
                    position: duration ? { duration, elapsed: element.currentTime, rate: element.paused ? 0 : element.playbackRate } : null,
                    session
                });
            };
            const schedule = () => { clearTimeout(timer); timer = setTimeout(report, 60); };
            addEventListener("pagehide", () => {
                if (reported) window.webkit.messageHandlers.\(handlerName).postMessage({ frame, gone: true });
            });
            document.addEventListener("aero:media-session", (event) => {
                try { session = JSON.parse(event.detail); } catch { session = null; }
                schedule();
            });
            for (const type of ["play", "playing", "pause", "ended", "emptied", "seeked", "ratechange", "durationchange", "loadedmetadata"]) {
                document.addEventListener(type, (event) => {
                    if (!(event.target instanceof HTMLMediaElement)) return;
                    if (type === "play" || type === "playing") last = event.target;
                    schedule();
                }, true);
            }
            globalThis.aeroMediaAction = (action) => {
                if (session?.actions?.includes(action)) {
                    document.dispatchEvent(new CustomEvent("aero:media-action", { detail: action }));
                    return true;
                }
                const element = media();
                if (!element) return false;
                switch (action) {
                case "play": element.play().catch(() => {}); return true;
                case "pause": element.pause(); return true;
                case "seekbackward": element.currentTime = Math.max(0, element.currentTime - 10); return true;
                case "seekforward": element.currentTime = Math.min(element.duration || Infinity, element.currentTime + 10); return true;
                default: return false;
                }
            };
        })();
        """, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: PageScripts.world)

    /// Frames a page may report media from; more are ignored.
    nonisolated static let maximumFrames = 32
    nonisolated static let maximumFrameTokenLength = 64

    static let perform = "return globalThis.aeroMediaAction?.(action) ?? false;"
}

final class MediaBridge: NSObject, WKScriptMessageHandler {
    @MainActor
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let page = message.webView?.navigationDelegate as? BrowserPage else { return }
        page.receiveMediaReport(message.body, from: message.frameInfo)
    }
}

extension BrowserPage {
    /// The page's report is untrusted: texts are bounded, artwork is a website address, numbers are finite. WebKit's own
    /// playback state settles whether it plays, for media a script cannot see, such as an element out of the document.
    /// Each frame reports under its own token; the page's media is the frame heard last, else one naming its media or
    /// holding an element, the main frame first.
    func receiveMediaReport(_ body: Any, from info: WKFrameInfo) {
        guard let fields = body as? [String: Any], let token = fields["frame"] as? String,
              !token.isEmpty, token.utf8.count <= MediaScripts.maximumFrameTokenLength else { return }
        if fields["gone"] as? Bool == true {
            mediaFrames[token] = nil
        } else {
            guard let report = MediaReport(body), mediaFrames[token] != nil || mediaFrames.count < MediaScripts.maximumFrames else { return }
            mediaFrames[token] = MediaFrame(report: report, frame: info, update: mediaFrameUpdates + 1)
        }
        mediaFrameUpdates += 1
        guard let chosen = mediaFrames.values.max(by: { $0.rank < $1.rank }) else { return updateMedia(nil) }
        mediaFrame = chosen.frame
        let update = mediaFrameUpdates
        Task { [weak self] in
            guard let self else { return }
            let state = await webView.requestMediaPlaybackState()
            // A later report, or a new document, has its own answer: this one is stale.
            guard update == mediaFrameUpdates else { return }
            let report = chosen.report
            updateMedia(report.media(isPlaying: report.playing || (state == .playing && chosen.frame.isMainFrame), previous: activity.media, now: .now))
        }
    }

    /// Asks the page to play, pause or skip: the site's own handler when it gives one, else its media element. Without
    /// either, WebKit pauses the page's media itself.
    public func perform(_ action: PageMediaAction) {
        Task { [weak self] in
            guard let self else { return }
            let handled = try? await webView.callAsyncJavaScript(MediaScripts.perform, arguments: ["action": action.rawValue], in: mediaFrame,
                                                                 contentWorld: PageScripts.world)
            if handled as? Bool != true, action == .pause { await webView.pauseAllMediaPlayback() }
        }
    }

    /// Mutes or unmutes the camera or the microphone the page uses; the page keeps them, and its call goes on.
    public func setCaptureMuted(camera: Bool? = nil, microphone: Bool? = nil) {
        if let camera, activity.camera != .off { webView.setCameraCaptureState(camera ? .muted : .active) }
        if let microphone, activity.microphone != .off { webView.setMicrophoneCaptureState(microphone ? .muted : .active) }
    }

    func observeCapture() -> [NSKeyValueObservation] {
        let update: @Sendable (WKWebView, Any) -> Void = { [weak self] webView, _ in
            MainActor.assumeIsolated { self?.updateCapture(camera: webView.cameraCaptureState, microphone: webView.microphoneCaptureState) }
        }
        return [webView.observe(\.cameraCaptureState, changeHandler: update), webView.observe(\.microphoneCaptureState, changeHandler: update)]
    }

    /// A new document starts with no media until it reports some.
    func resetMedia() {
        mediaFrames = [:]
        mediaFrameUpdates += 1
        mediaFrame = nil
        updateMedia(nil)
    }

    private func updateCapture(camera: WKMediaCaptureState, microphone: WKMediaCaptureState) {
        var next = activity
        next.camera = CaptureState(camera)
        next.microphone = CaptureState(microphone)
        setActivity(next)
    }

    private func updateMedia(_ media: PageMedia?) {
        var next = activity
        next.media = media
        setActivity(next)
    }

    private func setActivity(_ next: PageActivity) {
        guard next != activity else { return }
        activity = next
        onActivity?(next)
    }
}

private extension CaptureState {
    init(_ state: WKMediaCaptureState) {
        switch state {
        case .active: self = .active
        case .muted: self = .muted
        default: self = .off
        }
    }
}

/// A frame's last report, and how recent it is.
struct MediaFrame {
    let report: MediaReport
    let frame: WKFrameInfo
    let update: Int

    /// Heard before merely playing, playing before naming its media or holding an element, the main frame first, then
    /// the latest.
    var rank: (Int, Int, Int) {
        let report = report
        let heard = report.playing && (report.audible || report.title != nil)
        let level = heard ? 3 : report.playing ? 2 : report.title != nil || report.hasElement ? 1 : 0
        return (level, frame.isMainFrame ? 1 : 0, update)
    }
}

/// A media report as the page script sends it, once checked.
struct MediaReport {
    var playing: Bool
    var audible: Bool
    var hasElement: Bool
    var title: String?
    var artist: String?
    var album: String?
    var artwork: URL?
    var actions: Set<PageMediaAction>
    var hasSession: Bool
    var position: (elapsed: Double, duration: Double, rate: Double)?

    init?(_ body: Any) {
        guard let body = body as? [String: Any], let playing = body["playing"] as? Bool, let hasElement = body["hasElement"] as? Bool else { return nil }
        self.playing = playing
        self.hasElement = hasElement
        audible = body["audible"] as? Bool ?? false
        let session = body["session"] as? [String: Any]
        hasSession = session != nil
        title = Self.text(session?["title"])
        artist = Self.text(session?["artist"])
        album = Self.text(session?["album"])
        artwork = Self.largestArtwork(session?["artwork"])
        actions = Set((session?["actions"] as? [Any] ?? []).compactMap { ($0 as? String).flatMap(PageMediaAction.init(rawValue:)) })
        // The site's own position first: an element may be an advert or a preview.
        position = Self.position(session?["position"]) ?? Self.position(body["position"])
    }

    /// The report as the player shows it; heard, it began playing now, unless it already was.
    func media(isPlaying: Bool, previous: PageMedia?, now: Date) -> PageMedia? {
        guard isPlaying || hasElement || title != nil else { return nil }
        // A site naming what it plays means it to be heard, whatever its element says.
        let isAudible = audible || title != nil
        let wasHeard = previous.map { $0.isPlaying && $0.isAudible } ?? false
        let startedAt = isPlaying && isAudible ? (wasHeard ? previous?.startedAt : now) : previous?.startedAt
        return PageMedia(isPlaying: isPlaying, isAudible: isAudible, title: title, artist: artist, album: album, artwork: artwork, actions: actions,
                         position: position.map { PlaybackPosition(elapsed: $0.elapsed, duration: $0.duration, rate: isPlaying ? $0.rate : 0, date: now) },
                         startedAt: startedAt)
    }

    private static func text(_ value: Any?) -> String? {
        guard let text = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return String(text.prefix(MediaScripts.maximumTextLength))
    }

    /// The artwork of the largest declared size, else the last listed, as sites list them smallest first.
    private static func largestArtwork(_ value: Any?) -> URL? {
        let images = (value as? [Any] ?? []).compactMap { item -> (url: URL, size: Int)? in
            guard let image = item as? [String: Any], let source = image["src"] as? String, source.utf8.count <= MediaScripts.maximumAddressLength,
                  let url = URL(string: source), NavigationInput.isWebURL(url) else { return nil }
            let sizes = (image["sizes"] as? String ?? "").split(separator: " ").compactMap { $0.split(separator: "x").first.flatMap { Int($0) } }
            return (url, sizes.max() ?? 0)
        }
        return images.enumerated().max { ($0.element.size, $0.offset) < ($1.element.size, $1.offset) }?.element.url
    }

    private static func position(_ value: Any?) -> (elapsed: Double, duration: Double, rate: Double)? {
        guard let position = value as? [String: Any], let duration = (position["duration"] as? NSNumber)?.doubleValue,
              duration.isFinite, duration > 0 else { return nil }
        let elapsed = (position["elapsed"] as? NSNumber)?.doubleValue ?? 0
        let rate = (position["rate"] as? NSNumber)?.doubleValue ?? 1
        guard elapsed.isFinite, rate.isFinite else { return nil }
        return (min(max(0, elapsed), duration), duration, rate)
    }
}
