import AppKit
import BrowserCore
import SwiftUI

/// The spaces' pages side by side. A horizontal two-finger swipe drags them and, released past
/// `threshold`, moves to the neighbouring space; a click in the footer slides there. Only the
/// selected page and its neighbours exist, so other spaces cost nothing.
struct SpacePager: View {
    /// How far a swipe must go, as a share of the page width, to change space.
    private static let threshold: CGFloat = 0.25
    /// Dragging past the first or last page resists by this factor.
    private static let edgeResistance: CGFloat = 0.25

    let browser: BrowserModel
    @State private var offset: CGFloat = 0
    @State private var width: CGFloat = 0
    @State private var feedbackStep = 0
    @Environment(\.layoutDirection) private var layoutDirection
    @Environment(\.browserReduceMotion) private var reduceMotion

    private var direction: CGFloat { layoutDirection == .rightToLeft ? -1 : 1 }
    private var spaces: [BrowserSpace] { browser.session.spaces }
    private var index: Int { spaces.firstIndex { $0.id == browser.window.selectedSpaceID } ?? 0 }

    var body: some View {
        let index = index
        let lower = max(0, index - 1)
        let upper = min(spaces.count, index + 2)
        ZStack {
            ForEach(Array(spaces[lower..<upper].enumerated()), id: \.element.id) { position, space in
                // Neighbours are off screen, so VoiceOver skips them too.
                SpacePage(browser: browser, space: space)
                    .equatable()
                    .offset(x: CGFloat(position + lower - index) * width * direction + offset)
                    .accessibilityHidden(position + lower != index)
            }
        }
        .clipped()
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .background(HorizontalSwipe(onChange: drag, onEnd: release))
        .onChange(of: index) { old, new in
            // The pages move to the new selection from where they were, dragged or not.
            offset += CGFloat(max(-1, min(1, new - old))) * width * direction
            settle()
        }
        .accessibilityIdentifier("sidebar.pages")
    }

    private func drag(by delta: CGFloat) {
        let logicalOffset = (offset + delta) * direction
        let atEdge = (logicalOffset > 0 && index == 0) || (logicalOffset < 0 && index == spaces.count - 1)
        let proposed = offset + (atEdge ? delta * Self.edgeResistance : delta)
        let limit = width * (atEdge ? Self.edgeResistance : 1)
        offset = max(-limit, min(limit, proposed))
        let step = destinationStep
        if step != 0, step != feedbackStep {
            feedbackStep = step
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
    }

    private var destinationStep: Int {
        guard width > 0 else { return 0 }
        let logicalOffset = offset * direction
        let step = logicalOffset < -width * Self.threshold ? 1 : logicalOffset > width * Self.threshold ? -1 : 0
        return spaces.indices.contains(index + step) ? step : 0
    }

    private func release(cancelled: Bool) {
        defer { feedbackStep = 0 }
        guard !cancelled else { settle(); return }
        let step = destinationStep
        guard step != 0 else { settle(); return }
        let target = spaces[index + step].id
        browser.switchSpace(target)
        if browser.window.selectedSpaceID == target {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        } else { settle() }
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
    let onEnd: (Bool) -> Void

    func makeNSView(context: Context) -> SwipeView { SwipeView() }

    func updateNSView(_ view: SwipeView, context: Context) {
        view.onChange = onChange
        view.onEnd = onEnd
    }

    final class SwipeView: NSView {
        private static let wheelPause = Duration.milliseconds(150)

        var onChange: (CGFloat) -> Void = { _ in }
        var onEnd: (Bool) -> Void = { _ in }
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
            wheelEnd?.cancel()
            wheelEnd = nil
            if claimed { onEnd(true) }
            claimed = false
            ownsMomentum = false
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
                let cancelled = event.phase.contains(.cancelled)
                ownsMomentum = !cancelled
                onEnd(cancelled)
            } else if isWheel {
                wheelEnd?.cancel()
                wheelEnd = Task { [weak self] in
                    do { try await Task.sleep(for: Self.wheelPause) } catch { return }
                    self?.claimed = false
                    self?.onEnd(false)
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
