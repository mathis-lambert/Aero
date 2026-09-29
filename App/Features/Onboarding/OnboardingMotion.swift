import BrowserStorage
import SwiftUI

extension View {
    /// Records where this view is in the onboarding's coordinate space, for flights and ripples.
    func onboardingFrame(_ key: String, in onboarding: OnboardingModel) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named(OnboardingView.space)) } action: { onboarding.frames[key] = $0 }
    }
}

/// A serif title whose words arrive one after another; read as one sentence.
struct Headline: View {
    let text: LocalizedStringResource
    var large = false
    @State private var shown = false
    @Environment(\.browserReduceMotion) private var reduceMotion

    init(_ text: LocalizedStringResource, large: Bool = false) {
        self.text = text
        self.large = large
    }

    var body: some View {
        let size: CGFloat = large ? 58 : 40
        let sentence = String(localized: text)
        let words = sentence.split(separator: " ").map(String.init)
        FlowLayout(spacing: size * 0.24, lineSpacing: size * 0.12, fallbackWidth: 376) {
            ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                Text(verbatim: word)
                    .font(BrandType.title(size))
                    .opacity(shown ? 1 : 0)
                    .offset(y: shown ? 0 : size * 0.32)
                    .animation(reduceMotion ? nil : .spring(duration: 0.8, bounce: 0.2).delay(0.1 + Double(index) * 0.06), value: shown)
            }
        }
        .padding(.bottom, large ? 20 : 14)
        .onAppear { shown = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: sentence))
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("onboarding.title")
    }
}

/// Favorites carried by the wind during the import: from the other browser's icon to their place in the preview.
struct FlyingFavicons: View {
    private static let most = 10

    let onboarding: OnboardingModel
    let layout: OnboardingLayout
    @State private var flights: [Flight] = []
    @Environment(\.browserReduceMotion) private var reduceMotion

    struct Flight: Identifiable {
        let id = UUID()
        let url: URL
        let from: CGPoint
        let to: CGPoint
        let delay: Double
        let lift: CGFloat
        let spin: Double
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(flights) { FlightView(flight: $0) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: onboarding.outcome?.favorites ?? 0) { old, new in
            guard old == 0, new > 0, onboarding.step == .importing, !reduceMotion else { return }
            launch()
        }
        .task(id: flights.map(\.id)) {
            guard !flights.isEmpty else { return }
            do { try await Task.sleep(for: .seconds(0.9 + Double(flights.count) * 0.07 + 0.3)) } catch { return }
            flights = []
        }
    }

    private func launch() {
        guard let origin = onboarding.frames["source.icon"], let profiles = onboarding.preview else { return }
        let target = layout.previewFavorites(for: .importing)
        var seen = Set<URL>()
        let links = profiles.flatMap(\.spaces).flatMap(\.allLinks).filter { seen.insert($0.url).inserted }
        flights = links.prefix(Self.most).enumerated().map { index, link in
            Flight(url: link.url, from: CGPoint(x: origin.midX, y: origin.midY),
                   to: CGPoint(x: target.minX + 16, y: target.minY + target.height * CGFloat(index) / CGFloat(max(1, min(links.count, Self.most) - 1))),
                   delay: Double(index) * 0.07, lift: .random(in: 30...70), spin: .random(in: -12...12))
        }
    }
}

private struct FlightView: View {
    let flight: FlyingFavicons.Flight
    @State private var launched = false

    var body: some View {
        FlyingTile(url: flight.url)
            .keyframeAnimator(initialValue: 0.0, trigger: launched) { content, progress in
                content.arcFlight(flight, progress: progress)
            } keyframes: { _ in
                KeyframeTrack {
                    // Waits its turn, then flies.
                    LinearKeyframe(0, duration: flight.delay)
                    CubicKeyframe(1, duration: 0.85)
                }
            }
            .onAppear { launched = true }
    }
}

private struct FlyingTile: View {
    let url: URL
    @Environment(\.palette) private var palette

    var body: some View {
        LetterFavicon(url: url)
            .frame(width: 26, height: 26)
            .background(palette.raised, in: RoundedRectangle(cornerRadius: 7))
            .shadow(color: .black.opacity(0.18), radius: 7, y: 4)
    }
}

private extension View {
    /// Along a quadratic curve that sweeps out along the wind, then settles into its place, swelling mid-flight and
    /// fading as it lands.
    nonisolated func arcFlight(_ flight: FlyingFavicons.Flight, progress k: Double) -> some View {
        let control = CGPoint(x: flight.to.x - flight.lift, y: flight.from.y - flight.lift * 0.3)
        let a = (1 - k) * (1 - k), b = 2 * (1 - k) * k, c = k * k
        let point = CGPoint(x: a * flight.from.x + b * control.x + c * flight.to.x, y: a * flight.from.y + b * control.y + c * flight.to.y)
        return scaleEffect(0.6 + sin(k * .pi) * 0.55)
            .rotationEffect(.degrees(flight.spin * sin(k * .pi)))
            .opacity(k <= 0 ? 0 : k < 0.1 ? k / 0.1 : k > 0.88 ? (1 - k) / 0.12 : 1)
            .position(point)
    }
}

/// A horizontal two-finger swipe on the trackpad, only while the Getting around step shows: the monitor is removed
/// with the view. One swipe gives one step; the direction follows the content, as scrolling does.
struct TwoFingerSwipe: NSViewRepresentable {
    let onSwipe: (Int) -> Void

    func makeNSView(context: Context) -> MonitorView { MonitorView(onSwipe: onSwipe) }
    func updateNSView(_ nsView: MonitorView, context: Context) { nsView.onSwipe = onSwipe }
    static func dismantleNSView(_ nsView: MonitorView, coordinator: ()) { nsView.stop() }

    final class MonitorView: NSView {
        private static let threshold: CGFloat = 60
        var onSwipe: (Int) -> Void
        private var monitor: Any?
        private var travel: CGFloat = 0
        private var fired = false

        init(onSwipe: @escaping (Int) -> Void) {
            self.onSwipe = onSwipe
            super.init(frame: .zero)
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                self?.handle(event) == true ? nil : event
            }
        }

        required init?(coder: NSCoder) { nil }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        /// Consumes horizontal trackpad scrolls in this window; everything else goes on.
        private func handle(_ event: NSEvent) -> Bool {
            guard event.window === window, event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty,
                  abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else { return false }
            if event.phase.contains(.began) { travel = 0; fired = false }
            travel += event.scrollingDeltaX
            if !fired, abs(travel) > Self.threshold {
                fired = true
                onSwipe(travel < 0 ? 1 : -1)
            }
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) { travel = 0; fired = false }
            return true
        }
    }
}

/// The app's own icon as Finder shows it: `NSApp.applicationIconImage` is blank before the Dock has drawn it.
enum AppIconImage {
    @MainActor static var current: NSImage { NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath) }
}
