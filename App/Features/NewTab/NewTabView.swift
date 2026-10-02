import AppKit
import BrowserCore
import SwiftUI

/// The control bar above the dithered wind, with the shelf of frequent sites and closed tabs while the
/// field is empty. See docs/BROWSING.md › New Tab and docs/PERFORMANCE.md › Display cadence and responsiveness.
struct NewTabView: View {
    /// The bar's top edge, as a share of the page height: a little above the middle.
    private static let barPosition: CGFloat = 0.4
    private static let shelfGap: CGFloat = 36
    /// Pointer movement wakes the wind at most this often, so hovering never floods the page with updates.
    private static let activityInterval: TimeInterval = 1
    /// Keys typed faster send no more rings, so a ring is never cut short to make room for another.
    private static let rippleInterval = WindArc.rippleLife / Double(WindArc.maximumRipples)
    private static let fieldFont = NSFont.systemFont(ofSize: BrowserDesign.Typography.fieldSize)

    let browser: BrowserModel
    @State private var controlBar: ControlBarModel
    @State private var shelf: NewTabShelf
    @State private var activity = 0
    @State private var lastActivity = Date.distantPast
    @State private var ripples: [WindArc.Ripple] = []
    @State private var shelfRevealed = false
    @Environment(\.browserReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    @Environment(\.layoutDirection) private var layoutDirection

    init(browser: BrowserModel) {
        self.browser = browser
        _controlBar = State(initialValue: ControlBarModel(browser: browser, presentation: nil))
        _shelf = State(initialValue: NewTabShelf(browser: browser))
    }

    var body: some View {
        let (ink, core, light) = Self.windColors(for: browser.accent, in: scheme)
        let typing = !controlBar.text.isEmpty
        GeometryReader { geometry in
            let size = geometry.size
            let barTop = size.height * Self.barPosition
            let barCenter = CGPoint(x: size.width / 2, y: barTop + ControlBarView.fieldHeight / 2)
            let arrival = WindArc.arrival(at: barCenter, in: size)
            ZStack(alignment: .top) {
                WindArc(ink: ink, core: core, light: light, size: size, activity: activity, ripples: ripples)
                NewTabShelfView(browser: browser, shelf: shelf, revealed: shelfRevealed)
                    .padding(.top, barTop + ControlBarView.fieldHeight + Self.shelfGap)
                    .opacity(typing ? 0 : 1)
                    .scaleEffect(typing && !reduceMotion ? 0.98 : 1, anchor: .top)
                    .allowsHitTesting(!typing)
                    .accessibilityHidden(typing)
                    .animation(.easeOut(duration: 0.16), value: typing)
                ControlBarView(browser: browser, model: controlBar, shelf: shelf, lightDelay: arrival)
                    .padding(.top, barTop)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task {
                guard !reduceMotion else { shelfRevealed = true; return }
                do { try await Task.sleep(for: .seconds(arrival)) } catch { return }
                shelfRevealed = true
            }
            .onChange(of: controlBar.text) { _, text in
                // Typing leaves the shelf, so Return never opens a tile the field hid.
                shelf.clearFocus()
                activity += 1
                if !text.isEmpty { ripple(from: caret(after: text, barBottom: barTop + ControlBarView.fieldHeight, in: size)) }
            }
        }
        // Here rather than on the shelf, which an empty shelf would never start.
        .task { await shelf.load() }
        .onContinuousHover { _ in
            let now = Date.now
            guard now.timeIntervalSince(lastActivity) >= Self.activityInterval else { return }
            lastActivity = now
            activity += 1
        }
    }

    /// The bottom of the bar under the caret, which follows the end of the text, as near as the field shows it.
    private func caret(after text: String, barBottom: CGFloat, in size: CGSize) -> CGPoint {
        let barWidth = min(ControlBarView.width, size.width - 2 * ControlBarView.margin)
        let textWidth = (text as NSString).size(withAttributes: [.font: Self.fieldFont]).width
        let leading = (size.width - barWidth) / 2 + ControlBarView.textLeading + min(textWidth, barWidth - 2 * ControlBarView.textLeading)
        return CGPoint(x: layoutDirection == .rightToLeft ? size.width - leading : leading, y: barBottom)
    }

    private func ripple(from origin: CGPoint) {
        let now = Date.now
        ripples.removeAll { now.timeIntervalSince($0.date) >= WindArc.rippleLife }
        guard ripples.count < WindArc.maximumRipples,
              now.timeIntervalSince(ripples.last?.date ?? .distantPast) >= Self.rippleInterval else { return }
        ripples.append(WindArc.Ripple(origin: origin, date: now))
    }

    /// On the dark canvas the dots take the luminous accent and the densest glow toward white; on the light canvas the
    /// sparse dots are paler and the densest carry the full tint. The onboarding's browser preview shares them.
    static func windColors(for accent: SpaceColor, in scheme: ColorScheme) -> (ink: Color, core: Color, light: Color) {
        let light = accent.light(in: scheme)
        let ink = scheme == .dark ? light : accent.tint.mix(with: .white, by: 0.35)
        let core = scheme == .dark ? light.mix(with: .white, by: 0.45) : accent.tint
        return (ink, core, light)
    }
}
