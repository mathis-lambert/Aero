import AppKit
import BrowserWebKit
import SwiftUI

/// A new download's file thrown in an arc into the downloads button. See docs/PROFILES.md › Downloads.
enum DownloadFlight {
    static let duration: TimeInterval = 0.9
}

extension View {
    /// Marks the downloads button as where thrown files land.
    func downloadsTarget() -> some View {
        anchorPreference(key: DownloadsTargetKey.self, value: .center) { $0 }
    }

    /// Throws each new download's file from the pointer into the downloads target, if one is shown.
    /// Applied to the window's root view.
    func downloadFlights(_ downloads: DownloadCoordinator) -> some View {
        modifier(DownloadFlights(downloads: downloads))
    }
}

private struct DownloadsTargetKey: PreferenceKey {
    static let defaultValue: Anchor<CGPoint>? = nil

    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
        value = value ?? nextValue()
    }
}

private struct DownloadFlights: ViewModifier {
    private struct Flight: Identifiable {
        let id: BrowserDownload.ID
        let filename: String
        /// The pointer in the window, or `nil` to start from its center.
        let start: CGPoint?
    }

    let downloads: DownloadCoordinator
    @State private var flights: [Flight] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(DownloadsTargetKey.self) { target in
                GeometryReader { proxy in
                    if let target {
                        let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
                        ForEach(flights) { flight in
                            ThrownFile(filename: flight.filename, start: flight.start ?? center, end: proxy[target])
                        }
                    }
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .onChange(of: downloads.lastStarted) { _, id in
                guard let id, !reduceMotion, let download = downloads.downloads.first(where: { $0.id == id }) else { return }
                flights.append(Flight(id: id, filename: download.filename, start: Self.pointer()))
                // Each flight owns its end, even when no target was shown to land on.
                Task {
                    try? await Task.sleep(for: .seconds(DownloadFlight.duration))
                    flights.removeAll { $0.id == id }
                }
            }
    }

    /// The pointer in the main window's top-left coordinates, when it is inside the window.
    private static func pointer() -> CGPoint? {
        guard let window = WindowConfiguration.mainWindow, let bounds = window.contentView?.bounds else { return nil }
        let point = window.convertPoint(fromScreen: NSEvent.mouseLocation)
        guard bounds.contains(point) else { return nil }
        return CGPoint(x: point.x, y: bounds.height - point.y)
    }
}

private struct ThrownFile: View {
    private static let size: CGFloat = 56
    /// Accelerates into the button, like a throw falling into a bin.
    private static let curve = Animation.timingCurve(0.35, 0, 0.8, 0.6, duration: DownloadFlight.duration)

    let filename: String
    let start: CGPoint
    let end: CGPoint
    @State private var progress = 0.0

    var body: some View {
        FileIcon(filename: filename, size: Self.size)
            .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
            .modifier(Throw(progress: progress, start: start, end: end))
            .onAppear { withAnimation(Self.curve) { progress = 1 } }
    }
}

/// Everything the throw changes, from one progress value.
private struct Throw: ViewModifier, @MainActor Animatable {
    /// How far the file rises from where it starts before falling, and how close to the top it may go.
    private static let lift: CGFloat = 130
    private static let ceiling: CGFloat = 24
    /// The file swells a little as it leaves, then shrinks into the button.
    private static let startScale = 0.9
    private static let peakScale = 1.1
    private static let peak = 0.2
    private static let landedScale = 0.45

    var progress: Double
    let start: CGPoint
    let end: CGPoint

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let t = progress
        // The rise happens early, near the start, so the fall into the button reads as a throw.
        let control = CGPoint(x: start.x + (end.x - start.x) * 0.3, y: max(start.y - Self.lift, Self.ceiling))
        let point = CGPoint(x: bezier(start.x, control.x, end.x, t), y: bezier(start.y, control.y, end.y, t))
        content
            .scaleEffect(t < Self.peak
                ? Self.startScale + (Self.peakScale - Self.startScale) * t / Self.peak
                : Self.peakScale + (Self.landedScale - Self.peakScale) * (t - Self.peak) / (1 - Self.peak))
            // Appears at once and fades only as it enters the button.
            .opacity(min(1, t / 0.06, (1 - t) / 0.08))
            .position(point)
    }

    private func bezier(_ a: CGFloat, _ b: CGFloat, _ c: CGFloat, _ t: Double) -> CGFloat {
        let t = CGFloat(t)
        return (1 - t) * (1 - t) * a + 2 * (1 - t) * t * b + t * t * c
    }
}
