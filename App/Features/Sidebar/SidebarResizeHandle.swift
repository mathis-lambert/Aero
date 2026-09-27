import AppKit
import SwiftUI

/// Native divider tracking and cursor feedback, without a window-wide event monitor.
struct SidebarResizeHandle: View {
    let width: CGFloat
    let maximum: CGFloat
    let onChange: (CGFloat) -> Void
    let onEnd: (CGFloat?) -> Void
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        DividerDrag(width: width, maximum: maximum, rightToLeft: layoutDirection == .rightToLeft,
                    onChange: onChange, onEnd: onEnd)
            .frame(width: 8)
            .accessibilityElement()
            .accessibilityLabel("Resize sidebar")
            .accessibilityValue(Text("\(Int(width)) points"))
            .accessibilityAdjustableAction { direction in
                onEnd(min(maximum, max(BrowserDesign.sidebarWidth, width + (direction == .increment ? 20 : -20))))
            }
            .accessibilityAction(named: Text("Hide sidebar")) { onEnd(nil) }
            .accessibilityIdentifier("sidebar.resize")
    }
}

private struct DividerDrag: NSViewRepresentable {
    let width: CGFloat
    let maximum: CGFloat
    let rightToLeft: Bool
    let onChange: (CGFloat) -> Void
    let onEnd: (CGFloat?) -> Void

    func makeNSView(context: Context) -> DividerView { DividerView() }

    func updateNSView(_ view: DividerView, context: Context) {
        view.configuration = self
    }

    final class DividerView: NSView {
        var configuration: DividerDrag?
        private var startX: CGFloat?
        private var startWidth: CGFloat = 0
        private var reached: Set<Limit> = []
        private enum Limit: Hashable { case minimum, maximum, collapse }

        override var mouseDownCanMoveWindow: Bool { false }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }

        override func mouseDown(with event: NSEvent) {
            guard let configuration else { return }
            startX = event.locationInWindow.x
            startWidth = configuration.width
            reached = []
        }

        override func mouseDragged(with event: NSEvent) {
            guard let configuration, let proposed = proposedWidth(event) else { return }
            if proposed <= BrowserDesign.sidebarWidth { feedback(.minimum) }
            if proposed >= configuration.maximum { feedback(.maximum) }
            configuration.onChange(clamp(proposed, maximum: configuration.maximum))
        }

        override func mouseUp(with event: NSEvent) {
            guard let configuration, let proposed = proposedWidth(event) else { return }
            startX = nil
            if proposed < BrowserDesign.sidebarWidth / 2 {
                feedback(.collapse)
                configuration.onEnd(nil)
            } else {
                configuration.onEnd(clamp(proposed, maximum: configuration.maximum))
            }
            reached = []
        }

        private func proposedWidth(_ event: NSEvent) -> CGFloat? {
            guard let startX, let configuration else { return nil }
            return startWidth + (event.locationInWindow.x - startX) * (configuration.rightToLeft ? -1 : 1)
        }

        private func clamp(_ width: CGFloat, maximum: CGFloat) -> CGFloat {
            min(maximum, max(BrowserDesign.sidebarWidth, width))
        }

        private func feedback(_ limit: Limit) {
            guard reached.insert(limit).inserted else { return }
            NSHapticFeedbackManager.defaultPerformer.perform(
                limit == .collapse ? .generic : .alignment, performanceTime: .now
            )
        }
    }
}
