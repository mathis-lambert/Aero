import AppKit
import BrowserCore
import BrowserWebKit
import SwiftUI

/// Above the sidebar's footer: the tabs off screen using the camera or the microphone, then the player of the media
/// that began playing last in a tab off screen (docs/MEDIA.md). Each comes up from the footer and goes back into it.
struct MediaDock: View {
    let browser: BrowserModel
    @Environment(\.browserReduceMotion) private var reduceMotion

    var body: some View {
        let capturing = browser.capturingTabs
        let nowPlaying = browser.nowPlaying
        VStack(spacing: 6) {
            ForEach(capturing, id: \.tab.id) { item in
                CaptureRow(browser: browser, tab: item.tab, activity: item.activity)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let nowPlaying {
                MediaPlayer(browser: browser, nowPlaying: nowPlaying)
                    .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .scale(scale: 0.9, anchor: .bottom)).combined(with: .opacity),
                                            removal: .scale(scale: 0.9, anchor: .bottom).combined(with: .opacity)))
            }
        }
        .padding(.horizontal, BrowserDesign.sidebarInset)
        .padding(.top, capturing.isEmpty && nowPlaying == nil ? 0 : 6)
        .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.28), value: nowPlaying?.tab.id)
        .animation(reduceMotion ? nil : BrowserDesign.motion, value: capturing.map(\.tab.id))
    }
}

/// The player, one compact row: the artwork, which leans back while paused and springs forward as it plays, the track
/// and who plays it, then Play or Pause, ringed with where the media is, and Next, Previous joining them under the
/// pointer. The glass stays neutral so the text reads; the artwork's color glows behind it while it plays. A click on
/// the artwork or the title shows the tab.
struct MediaPlayer: View {
    private static let artworkSize: CGFloat = 32
    /// Around the row, the same on every side, so the artwork sits as far from each edge.
    private static let inset: CGFloat = 6
    private static let radius: CGFloat = artworkSize / 2 * 0.45 + inset

    let browser: BrowserModel
    let nowPlaying: NowPlaying
    @State private var hovered = false
    @Environment(\.palette) private var palette
    @Environment(\.browserReduceMotion) private var reduceMotion

    var body: some View {
        let media = nowPlaying.media, tab = nowPlaying.tab
        let artwork = media.artwork.flatMap(browser.activities.artwork(at:))
        let tint = Color(nsColor: Self.tint(artwork?.color ?? browser.faviconKey(for: tab).flatMap { browser.favicons.favicon(for: $0).color },
                                            else: NSColor(browser.accent.tint)))
        HStack(spacing: 4) {
            HStack(spacing: 8) {
                artworkView(artwork, tab: tab, playing: media.isPlaying)
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: media.title ?? tab.displayTitle)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    Text(verbatim: media.artist ?? tab.url.siteName)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(palette.secondary)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentTransition(.opacity)
            }
            .contentShape(Rectangle())
            .onTapGesture { browser.showTab(tab) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(Text("Shows the tab"))
            controls(media, tab: tab, tint: tint)
        }
        .padding(Self.inset)
        .browserGlass(.control, radius: Self.radius)
        .glassGlow(media.isPlaying ? tint : .clear, radius: Self.radius)
        .overlay(alignment: .topTrailing) {
            if hovered {
                Button { browser.dismissPlayer() } label: {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).frame(width: 18, height: 18)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .offset(x: 5, y: -5)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel(Text("Close Player"))
                .accessibilityIdentifier("media.close")
            }
        }
        .onHover { hovered = $0 }
        .animation(reduceMotion ? nil : BrowserDesign.hover, value: hovered)
        .animation(reduceMotion ? nil : .spring(duration: 0.4, bounce: 0.35), value: media.isPlaying)
        .animation(reduceMotion ? nil : BrowserDesign.motion, value: media.artwork)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Now playing"))
        .accessibilityIdentifier("media.player")
    }

    /// The artwork's color when it has one: a grey or a white would wash the glass out under the title, so the space's
    /// color stands in.
    private static func tint(_ color: NSColor?, else fallback: NSColor) -> NSColor {
        guard let color = color?.usingColorSpace(.sRGB), color.saturationComponent >= 0.25 else { return fallback }
        return color
    }

    private func artworkView(_ artwork: PageActivities.Artwork?, tab: BrowserTab, playing: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        return Group {
            if let artwork {
                Image(nsImage: artwork.image).resizable().scaledToFill()
            } else {
                FaviconView(cache: browser.favicons, key: browser.faviconKey(for: tab), size: 18) {
                    Image(systemName: "music.note").font(.system(size: 13, weight: .semibold)).foregroundStyle(palette.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.fill)
            }
        }
        .frame(width: Self.artworkSize, height: Self.artworkSize)
        .clipShape(shape)
        .overlay { shape.strokeBorder(palette.line) }
        .id(nowPlaying.media.artwork)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
        .shadow(color: .black.opacity(playing ? 0.22 : 0.08), radius: playing ? 4 : 1.5, y: playing ? 2 : 1)
        .scaleEffect(playing ? 1 : 0.86)
        .rotation3DEffect(.degrees(playing ? 0 : 14), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
    }

    private func controls(_ media: PageMedia, tab: BrowserTab, tint: Color) -> some View {
        let hasPrevious = media.actions.contains(.previousTrack), hasNext = media.actions.contains(.nextTrack)
        return HStack(spacing: 0) {
            if hovered {
                control(hasPrevious ? "backward.fill" : "gobackward.10", label: hasPrevious ? "Previous Track" : "Back 10 Seconds", size: 28) {
                    browser.skipMedia(forward: false, on: tab.id)
                }
                .transition(.scale.combined(with: .opacity))
            }
            control(media.isPlaying ? "pause.fill" : "play.fill", label: media.isPlaying ? "Pause" : "Play", size: 28) {
                browser.toggleMedia(on: tab.id)
            }
            .font(.system(size: 12, weight: .semibold))
            .overlay { if let position = media.position { PlaybackRing(position: position, playing: media.isPlaying, tint: tint) } }
            control(hasNext ? "forward.fill" : "goforward.10", label: hasNext ? "Next Track" : "Forward 10 Seconds", size: 28) {
                browser.skipMedia(forward: true, on: tab.id)
            }
        }
    }

    private func control(_ symbol: String, label: LocalizedStringKey, size: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(QuietButtonStyle(radius: size / 2))
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(palette.ink)
        .tooltip(Text(label))
        .accessibilityLabel(Text(label))
    }
}

/// Where the media is, as a ring filling around Play or Pause with the artwork's color. It moves on its own while
/// playing, from the position the page last gave, redrawn twice a second; paused, it stays still.
private struct PlaybackRing: View {
    let position: PlaybackPosition
    let playing: Bool
    let tint: Color
    @Environment(\.palette) private var palette

    var body: some View {
        // Paused, it cannot move: the timeline stops.
        TimelineView(.animation(minimumInterval: 0.5, paused: !playing)) { context in
            let now = playing ? context.date : position.date
            ZStack {
                Circle().stroke(palette.line, lineWidth: 2)
                Circle()
                    .trim(from: 0, to: position.elapsed(at: now) / max(position.duration, 1))
                    .stroke(tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.5), value: now)
            }
        }
        .padding(1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// A tab off screen using the camera or the microphone: who, and switches muting each; a click on its name shows it.
private struct CaptureRow: View {
    let browser: BrowserModel
    let tab: BrowserTab
    let activity: PageActivity
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            Button { browser.showTab(tab) } label: {
                HStack(spacing: 8) {
                    FaviconView(cache: browser.favicons, key: browser.faviconKey(for: tab), size: 14) {
                        Image(systemName: "globe").font(.system(size: 11)).foregroundStyle(palette.secondary)
                    }
                    Text(verbatim: tab.url.siteName).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if activity.camera != .off {
                toggle(on: activity.camera == .active, symbol: "video.fill", off: "video.slash.fill", color: .green,
                       label: activity.camera == .active ? "Turn Camera Off" : "Turn Camera On") {
                    browser.setCaptureMuted(tab.id, camera: activity.camera == .active)
                }
            }
            if activity.microphone != .off {
                toggle(on: activity.microphone == .active, symbol: "mic.fill", off: "mic.slash.fill", color: .orange,
                       label: activity.microphone == .active ? "Mute Microphone" : "Unmute Microphone") {
                    browser.setCaptureMuted(tab.id, microphone: activity.microphone == .active)
                }
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .frame(height: 32)
        .browserGlass(.control, radius: 10)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("media.capture")
    }

    private func toggle(on: Bool, symbol: String, off: String, color: Color, label: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: on ? symbol : off)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(on ? color : palette.secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 24, height: 24)
                .contentShape(Circle())
        }
        .buttonStyle(QuietButtonStyle(radius: 12))
        .tooltip(Text(label))
        .accessibilityLabel(Text(label))
    }
}

/// What a tab plays and records, beside its title: the camera and the microphone in the system's colors, and the
/// sound, moving while it plays, a click pausing or playing it.
struct ActivityIndicators: View {
    let browser: BrowserModel
    let tabID: UUID
    @Environment(\.palette) private var palette
    @Environment(\.browserReduceMotion) private var reduceMotion

    var body: some View {
        if let activity = browser.activity(of: tabID) {
            HStack(spacing: 2) {
                if activity.camera != .off {
                    Image(systemName: activity.camera == .active ? "video.fill" : "video.slash.fill")
                        .foregroundStyle(activity.camera == .active ? Color.green : palette.secondary)
                        .accessibilityLabel(Text("Using the camera"))
                }
                if activity.microphone != .off {
                    Image(systemName: activity.microphone == .active ? "mic.fill" : "mic.slash.fill")
                        .foregroundStyle(activity.microphone == .active ? Color.orange : palette.secondary)
                        .accessibilityLabel(Text("Using the microphone"))
                }
                if let media = activity.media, media.isPlaying, media.isAudible {
                    Button { browser.toggleMedia(on: tabID) } label: {
                        Image(systemName: "speaker.wave.2.fill")
                            .symbolEffect(.variableColor.iterative.dimInactiveLayers, isActive: !reduceMotion)
                            .foregroundStyle(palette.secondary)
                            .frame(width: 18, height: 18)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .tooltip(Text("Pause"))
                    .accessibilityLabel(Text("Playing sound, pause"))
                    .accessibilityIdentifier("sidebar.tab.sound")
                }
            }
            .font(.system(size: 10, weight: .semibold))
            .transition(.opacity)
        }
    }
}
