import AppKit
import BrowserCore
import SwiftUI

/// The profiles' pages side by side. A horizontal two-finger swipe drags them and, released past
/// `threshold`, moves to the neighbouring profile; a click in the footer slides there. Only the
/// selected page and its neighbours exist, so other profiles cost nothing.
struct ProfilePager: View {
    /// How far a swipe must go, as a share of the page width, to change profile.
    private static let threshold: CGFloat = 0.25
    /// Dragging past the first or last page resists by this factor.
    private static let edgeResistance: CGFloat = 0.25

    let browser: BrowserModel
    @State private var offset: CGFloat = 0
    @State private var width: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var profiles: [BrowserProfile] { browser.session.profiles }
    private var index: Int { profiles.firstIndex { $0.id == browser.window.selectedProfileID } ?? 0 }

    var body: some View {
        let index = index
        ZStack {
            ForEach(Array(profiles.enumerated()), id: \.element.id) { position, profile in
                if abs(position - index) <= 1, let space = browser.space(of: profile.id) {
                    ProfilePage(browser: browser, profile: profile, space: space)
                        .offset(x: CGFloat(position - index) * width + offset)
                }
            }
        }
        .clipped()
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .background(HorizontalSwipe(onChange: drag, onEnd: release))
        .onChange(of: index) { old, new in
            // The pages move to the new selection from where they were, dragged or not.
            offset += CGFloat(new - old) * width
            settle()
        }
        .accessibilityIdentifier("sidebar.pages")
    }

    private func drag(by delta: CGFloat) {
        let atEdge = (offset + delta > 0 && index == 0) || (offset + delta < 0 && index == profiles.count - 1)
        offset += atEdge ? delta * Self.edgeResistance : delta
    }

    private func release() {
        let step = offset < -width * Self.threshold ? 1 : offset > width * Self.threshold ? -1 : 0
        let target = index + step
        if step != 0, profiles.indices.contains(target) { browser.switchProfile(profiles[target].id) }
        else { settle() }
    }

    private func settle() {
        if reduceMotion { offset = 0 } else { withAnimation(BrowserDesign.motion) { offset = 0 } }
    }
}

/// Reports horizontal scrolls over its area before the views under the pointer see them: a
/// gesture that starts mostly horizontal belongs to the pager until it ends, momentum included;
/// any other scroll goes on to the tab list. A wheel without gesture phases ends after a pause.
private struct HorizontalSwipe: NSViewRepresentable {
    let onChange: (CGFloat) -> Void
    let onEnd: () -> Void

    func makeNSView(context: Context) -> SwipeView { SwipeView() }

    func updateNSView(_ view: SwipeView, context: Context) {
        view.onChange = onChange
        view.onEnd = onEnd
    }

    final class SwipeView: NSView {
        private static let wheelPause = Duration.milliseconds(150)

        var onChange: (CGFloat) -> Void = { _ in }
        var onEnd: () -> Void = {}
        private var monitor: Any?
        /// The current gesture, or wheel burst, is the pager's.
        private var claimed = false
        /// The momentum after a claimed gesture is the pager's too.
        private var ownsMomentum = false
        private var wheelEnd: Task<Void, Never>?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                return handle(event) ? nil : event
            }
        }

        /// Returns whether the event was consumed.
        private func handle(_ event: NSEvent) -> Bool {
            if !event.momentumPhase.isEmpty {
                let owned = ownsMomentum
                if event.momentumPhase.contains(.ended) { ownsMomentum = false }
                return owned
            }
            let isWheel = event.phase.isEmpty
            if event.phase.contains(.began) || (isWheel && !claimed) {
                ownsMomentum = false
                claimed = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) && event.window === window
                    && bounds.contains(convert(event.locationInWindow, from: nil))
            }
            guard claimed else { return false }
            onChange(event.scrollingDeltaX)
            if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
                claimed = false
                ownsMomentum = true
                onEnd()
            } else if isWheel {
                wheelEnd?.cancel()
                wheelEnd = Task { [weak self] in
                    do { try await Task.sleep(for: Self.wheelPause) } catch { return }
                    self?.claimed = false
                    self?.onEnd()
                }
            }
            return true
        }

        isolated deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
            wheelEnd?.cancel()
        }
    }
}
