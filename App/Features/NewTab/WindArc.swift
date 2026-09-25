import SwiftUI

/// The New Tab page's wind (`Wind.metal`): the GPU draws everything, the app only advances the time.
/// A gust carries its light to `target`, the control bar; the wind then drifts until `restDelay` after
/// the last `activity`, and holds still while the window is inactive, with Reduce Motion or in Low
/// Power Mode.
struct WindArc: View {
    /// The drift is slow: 30 frames per second look as smooth as the display's rate, for less work.
    private static let frameInterval: TimeInterval = 1.0 / 30
    private static let restDelay = Duration.seconds(20)
    /// The gust's speed, in points per second: fast, so little separates the wind from the bar; what
    /// it does to each point unfolds in its own time (the shader's gust timings).
    private static let gustSpeed: CGFloat = 2000
    /// The gust's origin below the page's bottom center, as a share of the page height.
    private static let originDrop: CGFloat = 0.15
    /// How long a point keeps changing after the gust reaches it, and the light after it arrives.
    private static let gustTail: TimeInterval = 1.2
    /// An intro time past everything: the gust is over and every dot has grown.
    private static let spent: Float = 1e4

    let ink: Color
    /// The color the densest dots move toward.
    let core: Color
    let light: Color
    /// Times the gust.
    let size: CGSize
    let target: CGPoint
    /// Changes when the person moves the pointer over the page.
    let activity: Int
    @State private var clock = WindClock()
    @State private var appeared = Date.now
    @State private var rising = true
    @State private var resting = false
    @Environment(\.displayScale) private var displayScale
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static func origin(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height * (1 + originDrop))
    }

    /// When the gust, and its light, reach `point` of a page of `size`, after the page appeared.
    static func arrival(at point: CGPoint, in size: CGSize) -> TimeInterval {
        let origin = origin(in: size)
        return hypot(point.x - origin.x, point.y - origin.y) / gustSpeed
    }

    private var drifts: Bool {
        !resting && !reduceMotion && activeState != .inactive && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: Self.frameInterval, paused: !(drifts || rising))) { timeline in
            let time = Float(clock.time(at: timeline.date))
            let intro = reduceMotion || !rising ? Self.spent : Float(timeline.date.timeIntervalSince(appeared))
            let pixel = Float(1 / displayScale)
            let origin = Self.origin(in: size)
            let speed = Float(Self.gustSpeed)
            Rectangle().visualEffect { [ink, core, light, target] content, proxy in
                content.colorEffect(ShaderLibrary.windArc(
                    .float2(proxy.size), .float(time), .float2(origin), .float2(target),
                    .float(intro), .float(speed), .color(ink), .color(core), .color(light), .float(pixel)))
            }
        }
        .onChange(of: drifts, initial: true) { _, drifts in clock.setRunning(drifts) }
        .task {
            appeared = .now
            // With Reduce Motion the page appears whole, so no frame runs for the gust.
            guard !reduceMotion else { rising = false; return }
            // Until the gust has crossed the whole page and every point has settled.
            let farthest = Self.arrival(at: .zero, in: size)
            do { try await Task.sleep(for: .seconds(farthest + Self.gustTail)) } catch { return }
            rising = false
        }
        .task(id: activity) {
            resting = false
            do { try await Task.sleep(for: Self.restDelay) } catch { return }
            resting = true
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The wind's own time: it stops while the wind rests, so drifting again continues from the same
/// shapes instead of jumping ahead.
private final class WindClock {
    private var elapsed: TimeInterval = 0
    private var resumed: Date?

    func setRunning(_ running: Bool, at date: Date = .now) {
        if running, resumed == nil { resumed = date }
        if !running, let resumed {
            elapsed += date.timeIntervalSince(resumed)
            self.resumed = nil
        }
    }

    func time(at date: Date) -> TimeInterval {
        elapsed + (resumed.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }
}
