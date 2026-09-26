import AppKit
import SwiftUI

extension View {
    /// The chrome's tooltip, in place of the system help tag: the label and the command's keys, shown
    /// once the pointer rests on the view. See docs/DESIGN.md › Tooltips and keycaps.
    func tooltip(_ text: Text, shortcut: KeyboardShortcut? = nil) -> some View {
        background(TooltipAnchor(text: text, shortcut: shortcut))
    }

    func tooltip(_ text: String, shortcut: KeyboardShortcut? = nil) -> some View {
        tooltip(Text(verbatim: text), shortcut: shortcut)
    }
}

private struct TooltipLabel: View {
    let text: Text
    let shortcut: KeyboardShortcut?
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            text.font(BrowserDesign.Typography.label).foregroundStyle(palette.ink)
            if let shortcut { Keycaps(shortcut) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .browserSurface(fill: palette.raised, border: palette.line, radius: BrowserDesign.Radius.control)
        .fixedSize()
    }
}

/// Tracks the pointer over the view it backs; the tracking area costs nothing until it moves there.
private struct TooltipAnchor: NSViewRepresentable {
    let text: Text
    let shortcut: KeyboardShortcut?

    func makeNSView(context: Context) -> AnchorView { AnchorView() }

    func updateNSView(_ view: AnchorView, context: Context) {
        view.label = TooltipLabel(text: text, shortcut: shortcut)
    }

    final class AnchorView: NSView {
        var label: TooltipLabel?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                                           owner: self))
        }

        override func mouseEntered(with event: NSEvent) { Tooltips.enter(self) }
        override func mouseExited(with event: NSEvent) { Tooltips.exit(self) }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil { Tooltips.exit(self) }
            super.viewWillMove(toWindow: newWindow)
        }

        /// The anchor's frame on screen.
        var screenFrame: NSRect? {
            window.map { $0.convertToScreen(convert(bounds, to: nil)) }
        }
    }
}

/// The one tooltip on screen, in a borderless panel so nothing clips it. After one hides, a
/// neighbour's shows at once for a moment, as the system's do.
@MainActor
private enum Tooltips {
    private static let delay = Duration.milliseconds(500)
    private static let warmth = Duration.milliseconds(600)
    private static let gap: CGFloat = 6

    private static weak var anchor: TooltipAnchor.AnchorView?
    private static var pending: Task<Void, Never>?
    private static var hiddenAt: ContinuousClock.Instant?
    private static var monitor: Any?
    private static let panel: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        panel.setAccessibilityIdentifier("tooltip")
        return panel
    }()

    static func enter(_ view: TooltipAnchor.AnchorView) {
        anchor = view
        pending?.cancel()
        let isWarm = panel.isVisible || hiddenAt.map { .now - $0 < warmth } == true
        pending = Task {
            if !isWarm { do { try await Task.sleep(for: delay) } catch { return } }
            show(for: view)
        }
        // Clicks, keys and scrolls end the tooltip; the monitor exists only while one is pending or shown.
        if monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]) { event in
                dismiss()
                return event
            }
        }
    }

    static func exit(_ view: TooltipAnchor.AnchorView) {
        guard anchor === view else { return }
        if panel.isVisible { hiddenAt = .now }
        dismiss()
    }

    private static func dismiss() {
        pending?.cancel()
        pending = nil
        anchor = nil
        panel.orderOut(nil)
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static func show(for view: TooltipAnchor.AnchorView) {
        guard anchor === view, NSApp.isActive, let label = view.label, let window = view.window,
              let frame = view.screenFrame, let screen = window.screen?.visibleFrame else { return }
        let content = NSHostingView(rootView: label)
        content.appearance = window.effectiveAppearance
        let size = content.fittingSize
        // Below the control, or above it near the bottom of the screen, always fully on screen.
        var origin = NSPoint(x: frame.midX - size.width / 2, y: frame.minY - gap - size.height)
        if origin.y < screen.minY { origin.y = frame.maxY + gap }
        origin.x = min(max(origin.x, screen.minX + gap), screen.maxX - gap - size.width)
        panel.contentView = content
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.invalidateShadow()
        panel.orderFront(nil)
    }
}
