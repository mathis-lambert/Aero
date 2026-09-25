import BrowserCore
import SwiftUI

/// The empty surface of a new tab: the control bar above a crescent of dithered wind, both in the
/// profile's accent. Each time the page appears a gust rises from below, blows the wind in and carries a
/// light to the bar, which lights up as it arrives; then only the wind drifts, while someone is there.
/// See docs/CONTROL_BAR.md › New Tab page.
struct NewTabView: View {
    /// The bar's top edge, as a share of the page height: a little above the middle.
    private static let barPosition: CGFloat = 0.4
    /// Pointer movement wakes the wind at most this often, so hovering never floods the page with updates.
    private static let activityInterval: TimeInterval = 1

    let browser: BrowserModel
    @State private var activity = 0
    @State private var lastActivity = Date.distantPast
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let color = browser.accent
        let light = color.light(in: scheme)
        // On the dark canvas the dots take the luminous accent and the densest glow toward white; on
        // the light canvas the sparse dots are paler and the densest carry the full tint.
        let ink = scheme == .dark ? light : color.tint.mix(with: .white, by: 0.35)
        let core = scheme == .dark ? light.mix(with: .white, by: 0.45) : color.tint
        GeometryReader { geometry in
            let size = geometry.size
            let barTop = size.height * Self.barPosition
            let barCenter = CGPoint(x: size.width / 2, y: barTop + ControlBarView.fieldHeight / 2)
            ZStack(alignment: .top) {
                WindArc(ink: ink, core: core, light: light, size: size, target: barCenter, activity: activity)
                ControlBarView(browser: browser, presentation: nil, lightDelay: WindArc.arrival(at: barCenter, in: size))
                    .padding(.top, barTop)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onContinuousHover { _ in
            let now = Date.now
            guard now.timeIntervalSince(lastActivity) >= Self.activityInterval else { return }
            lastActivity = now
            activity += 1
        }
    }
}
