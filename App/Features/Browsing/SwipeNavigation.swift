import BrowserCore
import BrowserWebKit
import SwiftUI

extension View {
    /// The swipe through the page's history (docs/BROWSING.md › Swiping through history): an arrow on glass coming in
    /// from the side the fingers move from, which fills as it reaches the threshold and, held there, opens into a wheel
    /// of the pages that way, which the fingers turn. It never takes a click: the fingers do it all.
    func swipeNavigation(_ browser: BrowserModel, page: BrowserPage) -> some View {
        overlay { SwipeNavigationOverlay(browser: browser, page: page) }
    }
}

private struct SwipeNavigationOverlay: View {
    private static let size: CGFloat = 44
    /// How far in the arrow comes at the threshold, from just out of sight.
    private static let reach: CGFloat = 72
    private static let motion = Animation.spring(duration: 0.26, bounce: 0.18)

    let browser: BrowserModel
    let page: BrowserPage
    @Environment(\.palette) private var palette
    @Environment(\.browserReduceMotion) private var reduceMotion
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        let swipe = page.swipe
        // Back comes from the leading side, as the page it brings back.
        let alignment: Alignment = swipe?.direction == .forward ? .trailing : .leading
        ZStack(alignment: alignment) {
            // The arrow gives way to the list, which grows out of where it was, the picked page at its height.
            if case .listing(let picked)? = swipe?.phase, let swipe {
                SwipeHistoryWheel(browser: browser, items: page.history(swipe.direction), picked: picked, drift: swipe.drift)
                    .padding(.horizontal, Self.reach - Self.size + 6)
                    .transition(.scale(scale: 0.25, anchor: alignment == .leading ? .leading : .trailing).combined(with: .opacity))
            } else if let swipe {
                arrow(swipe)
                    .offset(x: offset(swipe, leading: alignment == .leading))
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .animation(reduceMotion ? nil : Self.motion, value: swipe?.phase)
        .animation(reduceMotion ? nil : .interactiveSpring(duration: 0.18), value: swipe?.progress)
        .allowsHitTesting(false)
    }

    /// Just out of sight at rest, `reach` in at the threshold, a little further past it, slower.
    private func offset(_ swipe: PageSwipe, leading: Bool) -> CGFloat {
        let progress = min(swipe.progress, 1) + max(swipe.progress - 1, 0) * 0.25
        let inward = -Self.size + progress * (Self.reach + Self.size - 14)
        return leading == (layoutDirection == .leftToRight) ? inward : -inward
    }

    private func arrow(_ swipe: PageSwipe) -> some View {
        let ready = swipe.phase == .ready
        let accent = browser.accent.light(in: palette.scheme)
        return Image(systemName: swipe.direction == .back ? "arrow.backward" : "arrow.forward")
            .font(.system(size: 17, weight: ready ? .bold : .semibold))
            .foregroundStyle(ready ? .white : palette.ink)
            .frame(width: Self.size, height: Self.size)
            .background { Circle().fill(accent).scaleEffect(ready ? 1 : 0.001).opacity(ready ? 1 : 0) }
            .browserGlass(.control, radius: Self.size / 2)
            .scaleEffect(0.75 + 0.25 * min(swipe.progress, 1) + (ready ? 0.08 : 0))
            .opacity(min(1, swipe.progress * 2))
            .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
            .accessibilityHidden(true)
    }
}

/// The pages back or forward, nearest first, as a small wheel beside the arrow: the picked one, a little brighter, sits
/// at the arrow's height, and the others fade as they go from it. The whole panel floats with the fingers: up and down
/// as they turn it, stretching past either end, and a little sideways.
private struct SwipeHistoryWheel: View {
    private static let row: CGFloat = 26
    private static let width: CGFloat = 200
    /// How much of the fingers' sideways travel the panel follows, and how far at most.
    private static let sideways: CGFloat = 0.25
    private static let maximumSideways: CGFloat = 24

    let browser: BrowserModel
    let items: [PageHistoryItem]
    let picked: Int
    let drift: CGSize
    @Environment(\.palette) private var palette
    @Environment(\.browserReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let distance = abs(index - picked)
                HStack(spacing: 7) {
                    FaviconView(cache: browser.favicons, key: browser.profile.flatMap { FaviconKey(profileID: $0.id, url: item.url) }, size: 12) {
                        Image(systemName: "globe").font(.system(size: 10)).foregroundStyle(palette.secondary)
                    }
                    .frame(width: 14)
                    Text(verbatim: item.title.isEmpty ? item.url.siteName : item.title)
                        .font(.system(size: 11.5, weight: index == picked ? .medium : .regular))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 8)
                .frame(height: Self.row)
                .background {
                    if index == picked { RoundedRectangle(cornerRadius: 7, style: .continuous).fill(palette.ink.opacity(0.12)) }
                }
                .opacity(max(0.3, 1 - 0.2 * Double(distance)))
            }
        }
        .padding(4)
        .frame(width: Self.width)
        .browserGlass(.panel, radius: 11)
        .shadow(color: .black.opacity(0.22), radius: 14, y: 5)
        // The picked page at the arrow's height, the middle of the page, carried along by the fingers.
        .offset(x: min(max(drift.width * Self.sideways, -Self.maximumSideways), Self.maximumSideways),
                y: (CGFloat(items.count - 1) / 2 - CGFloat(picked) - drift.height) * Self.row)
        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.16, dampingFraction: 0.86), value: drift)
        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.16, dampingFraction: 0.86), value: picked)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: items.indices.contains(picked) ? items[picked].title : ""))
        .accessibilityIdentifier("page.swipeHistory")
    }
}
