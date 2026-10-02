import SwiftUI

/// The New Tab page's wind (`Wind.metal`): the GPU draws everything, the app only advances the time.
/// A gust rises from below the page's center, quick at first and slowing as it spreads, and lights the
/// dots it reaches; the wind then drifts until `restDelay` after the last `activity`, and holds still
/// while the window is inactive, with Reduce Motion or in Low Power Mode. Each of the `ripples` sends a
/// ring through the dots.
struct WindArc: View {
    /// A ring sent through the dots, from the field's caret as a key is typed.
    struct Ripple: Equatable {
        let origin: CGPoint
        let date: Date
    }

    /// Slow decorative drift has a lower budget; the entrance and the rings follow the display cadence.
    private static let frameInterval: TimeInterval = 1.0 / 30
    private static let restDelay = Duration.seconds(20)
    /// How long the gust's front takes to cross the whole page, easing out: it reaches the bar in about
    /// a quarter of it.
    private static let introDuration: TimeInterval = 1.1
    /// The front's unevenness, which the farthest point may add to its distance (the shader's `ragged`).
    private static let ragged: CGFloat = 90
    /// The gust's origin below the page's bottom center, as a share of the page height.
    private static let originDrop: CGFloat = 0.15
    /// How long a point keeps changing after the front reaches it.
    private static let gustTail: TimeInterval = 1.2
    /// How long a ring lasts (the shader's `ringLife`), and how many can cross the page at once.
    static let rippleLife: TimeInterval = 1.2
    static let maximumRipples = 8
    /// An intro time past everything: the gust is over and every dot has grown.
    private static let spent: Float = 1e4

    let ink: Color
    /// The color the densest dots move toward.
    let core: Color
    let light: Color
    /// The page's size, from which the gust's arrival times follow.
    let size: CGSize
    /// Changes when the person moves the pointer over the page or types.
    let activity: Int
    var ripples: [Ripple] = []
    @State private var clock = WindClock()
    @State private var appeared = Date.now
    @State private var rising = true
    @State private var rippling = false
    @State private var resting = false
    @Environment(\.displayScale) private var displayScale
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.browserReduceMotion) private var reduceMotion

    private static func origin(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2, y: size.height * (1 + originDrop))
    }

    /// The distance the front covers: to the page's top corners, however uneven it is.
    private static func spread(in size: CGSize) -> CGFloat {
        hypot(size.width / 2, origin(in: size).y) + ragged
    }

    /// When the gust's front reaches `point` of a page of `size`, after the page appeared.
    static func arrival(at point: CGPoint, in size: CGSize) -> TimeInterval {
        let origin = origin(in: size)
        let share = min(1, hypot(point.x - origin.x, point.y - origin.y) / spread(in: size))
        return introDuration * (1 - cbrt(1 - share))
    }

    private var allowsMotion: Bool { !reduceMotion && activeState != .inactive }
    private var drifts: Bool { !resting && allowsMotion }
    private var lively: Bool { allowsMotion && (rising || rippling) }

    var body: some View {
        TimelineView(.animation(minimumInterval: lively ? nil : Self.frameInterval,
                                paused: !allowsMotion || !(drifts || lively))) { timeline in
            let time = Float(clock.time(at: timeline.date))
            let intro = !allowsMotion || !rising ? Self.spent : Float(timeline.date.timeIntervalSince(appeared))
            let pixel = Float(1 / displayScale)
            let origin = Self.origin(in: size)
            let spread = Float(Self.spread(in: size))
            let duration = Float(Self.introDuration)
            let rings = ringValues(at: timeline.date)
            Rectangle().visualEffect { [ink, core, light] content, proxy in
                content.colorEffect(ShaderLibrary.windArc(
                    .float2(proxy.size), .float(time), .float2(origin), .float(intro), .float(duration), .float(spread),
                    .floatArray(rings), .color(ink), .color(core), .color(light), .float(pixel)))
            }
        }
        .onChange(of: drifts, initial: true) { _, drifts in clock.setRunning(drifts) }
        .onChange(of: allowsMotion) { _, allowed in if !allowed { rising = false } }
        .task {
            appeared = .now
            // With Reduce Motion the page appears whole, so no frame runs for the gust.
            guard allowsMotion else { rising = false; return }
            // Until the front has crossed the whole page and every point has settled.
            do { try await Task.sleep(for: .seconds(Self.introDuration + Self.gustTail)) } catch { return }
            rising = false
        }
        .task(id: activity) {
            resting = false
            do { try await Task.sleep(for: Self.restDelay) } catch { return }
            resting = true
        }
        .task(id: ripples.last?.date) {
            guard let last = ripples.last?.date else { return }
            rippling = true
            do { try await Task.sleep(for: .seconds(max(0, Self.rippleLife - Date.now.timeIntervalSince(last)))) } catch { return }
            rippling = false
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Each live ring's origin and age; one spent ring when none is, since the shader takes no empty list.
    private func ringValues(at date: Date) -> [Float] {
        guard allowsMotion else { return [0, 0, Self.spent] }
        let values = ripples.flatMap { ripple -> [Float] in
            let age = date.timeIntervalSince(ripple.date)
            return age < Self.rippleLife ? [Float(ripple.origin.x), Float(ripple.origin.y), Float(max(0, age))] : []
        }
        return values.isEmpty ? [0, 0, Self.spent] : values
    }
}

/// The wind's own time: it stops while the wind rests, so drifting again continues from the same
/// shapes instead of jumping ahead.
private final class WindClock {
    private var elapsed: TimeInterval = 0
    private var resumed: Date?

    func setRunning(_ running: Bool) {
        let date = Date.now
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
