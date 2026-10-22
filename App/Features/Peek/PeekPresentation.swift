import AppKit
import BrowserCore
import BrowserWebKit
import SwiftUI

extension View {
    /// The page's frame, receding in the window behind the link previewed over it (docs/BROWSING.md › Peek).
    func peekPresentation(_ browser: BrowserModel) -> some View {
        modifier(PeekPresentation(browser: browser))
    }

    /// What the page shows, inside its frame, blurring and dimming behind the preview; the frame stays sharp.
    func peekBackdrop(_ browser: BrowserModel) -> some View {
        modifier(PeekBackdrop(browser: browser))
    }
}

/// The motion of a link's preview, as Apple's springs: quick to answer, settling without a wobble, with a touch of
/// overshoot where something lands.
private enum PeekMotion {
    /// Following the trackpad's pressure, a little behind it, so its steps read as one movement.
    static let following = Animation.interactiveSpring(response: 0.24, dampingFraction: 0.86)
    static let opening = Animation.spring(response: 0.42, dampingFraction: 0.76)
    static let closing = Animation.spring(response: 0.34, dampingFraction: 0.92)
    /// Growing into a tab, with a bounce as it lands.
    static let expanding = Animation.spring(response: 0.5, dampingFraction: 0.68)
    /// A pinch let go below its threshold, drawn back as by a magnet.
    static let settling = Animation.spring(response: 0.36, dampingFraction: 0.62)
    /// The buttons come after the card.
    static let chrome = Animation.spring(response: 0.36, dampingFraction: 0.72)
}

private struct PeekBackdrop: ViewModifier {
    private static let blur: CGFloat = 16

    let browser: BrowserModel
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        let receded = browser.window.peek == nil || browser.window.peekExpanded ? 0 : browser.window.peekReveal
        content
            .blur(radius: Self.blur * receded, opaque: true)
            .overlay {
                if receded > 0 { Color.black.opacity((palette.scheme == .dark ? 0.34 : 0.16) * receded).allowsHitTesting(false) }
            }
    }
}

/// The page's frame shrinks back in the window, what it shows blurring, while the preview grows out of the link over
/// it. The preview's page is laid out once, at the page's own size, and shown scaled down: pressing, opening, closing,
/// pinching and growing into a tab only move and scale it, so neither page lays out again, and the tab it becomes
/// already has its size. A press reveals it as far as the pressure goes, and the force click lets it spring open. A pinch
/// moves the card with the fingers and commits as soon as it goes far enough, or quickly enough, with a tick of the
/// trackpad: spread to grow the preview into a tab, with a bounce, pinch in to close it. With Reduce Motion it appears
/// and goes without moving.
private struct PeekPresentation: ViewModifier {
    /// The preview never takes more of the page than this, so the page shows around it.
    private static let largestScale: CGFloat = 0.86
    /// Room beside the preview for its buttons, and above and below it.
    private static let margin = CGSize(width: 60, height: 30)
    private static let radius: CGFloat = 16
    private static let recededScale: CGFloat = 0.93
    private static let buttonSize: CGFloat = 30
    /// How much of the way out a press brings the preview before the force click.
    private static let pressReach: CGFloat = 0.55
    /// The spread that grows the card over the page, as the fingers measure it; half of it opens the tab.
    private static let spreadToFill: CGFloat = 0.2
    private static let spreadToOpen: CGFloat = 0.1
    /// The pinch in that closes the preview.
    private static let pinchToClose: CGFloat = 0.12
    /// A pinch let go this fast, in its share of a spread per second, commits however far it went.
    private static let flickSpeed: CGFloat = 0.9

    let browser: BrowserModel
    /// The pinch as the fingers made it, and how fast it last moved.
    @State private var pinch: CGFloat = 0
    @State private var pinchSpeed: CGFloat = 0
    @State private var pinchTime: TimeInterval = 0
    /// A pinch on the preview keeps its events to its end, though it committed before: the page under it must not zoom.
    @State private var pinching = false
    @State private var showsChrome = false
    /// Made with the first preview: a state's initial value is built again at each update of the window.
    @State private var pinches: PinchMonitor?
    @Environment(\.browserReduceMotion) private var reduceMotion
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        let window = browser.window
        let peek = window.peek
        let receded = peek == nil || window.peekExpanded ? 0 : window.peekReveal
        content
            .scaleEffect(1 - (1 - Self.recededScale) * receded)
            // Around the preview, a click on the page or the window around it closes the preview.
            .overlay {
                if peek != nil {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { browser.dismissPeek() }
                        .allowsHitTesting(peek?.phase == .open || peek?.phase == .pressing)
                        .accessibilityHidden(true)
                }
            }
            .overlay {
                if let peek {
                    GeometryReader { area in preview(peek, in: area.size) }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("peek")
                }
            }
            .onChange(of: peek?.id, initial: true) { _, id in
                pinch = 0
                showsChrome = false
                guard let id else {
                    pinches?.stop()
                    return
                }
                if pinches == nil { pinches = PinchMonitor() }
                pinches?.start { followPinch($0) }
                // Opened at once, from the context menu: it springs open in the next frame, from its link.
                if window.peek?.phase == .open { Task { if browser.window.peek?.id == id { open() } } }
            }
            .onChange(of: window.peekPressure) { _, pressure in
                guard browser.window.peek?.phase == .pressing else { return }
                // Eased, so the first of the press moves the preview most, as a magnet draws it out.
                move(with: PeekMotion.following) { browser.window.peekReveal = Self.pressReach * pow(pressure, 0.7) } then: {}
            }
            .onChange(of: peek?.phase) { _, phase in
                guard let peek else { return }
                switch phase {
                case .open: open()
                case .closing:
                    showsChrome = false
                    move(with: PeekMotion.closing) { browser.window.peekReveal = 0; pinch = 0 } then: {
                        browser.endPeek(peek.id)
                        if let page = browser.currentPage { page.webView.window?.makeFirstResponder(page.webView) }
                    }
                case .expanding:
                    showsChrome = false
                    move(with: PeekMotion.expanding) { browser.window.peekExpanded = true; pinch = 0 } then: { browser.adoptPeek(peek.id) }
                case .pressing, nil: break
                }
            }
    }

    private func open() {
        move(with: PeekMotion.opening) { browser.window.peekReveal = 1 } then: {}
        move(with: PeekMotion.chrome.delay(reduceMotion ? 0 : 0.12)) { showsChrome = true } then: {}
        if let page = browser.window.peek?.page { page.webView.window?.makeFirstResponder(page.webView) }
    }

    private func preview(_ peek: Peek, in size: CGSize) -> some View {
        let window = browser.window
        let reveal = window.peekReveal
        let expanded = window.peekExpanded
        let shown = Self.shownScale(in: size)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        // In its link: the link's frame, or a little smaller than open when its place is unknown.
        let hiddenScale: CGFloat, hiddenOffset: CGSize
        if let origin = peek.origin, origin.width > 0 {
            hiddenScale = min(max(origin.width / size.width * 1.6, 0.12), shown * 0.5)
            hiddenOffset = CGSize(width: origin.midX - center.x, height: origin.midY - center.y)
        } else {
            hiddenScale = shown * 0.94
            hiddenOffset = .zero
        }
        // Spreading grows the card toward the page's size; pinching in shrinks it.
        let pinched = pinch > 0 ? 1 + (1 / shown - 1) * min(1, pinch / Self.spreadToFill) : 1 + pinch
        let scale = expanded ? 1 : min(1, (hiddenScale + (shown - hiddenScale) * reveal) * pinched)
        let offset = expanded ? .zero : CGSize(width: hiddenOffset.width * (1 - reveal), height: hiddenOffset.height * (1 - reveal))
        let opacity = expanded ? 1 : min(1, reveal * 3) * (pinch < 0 ? max(0, 1 + pinch * 2) : 1)
        let radius = expanded ? BrowserDesign.Radius.page : Self.radius
        let shape = RoundedRectangle(cornerRadius: radius / scale, style: .continuous)
        let card = CGRect(x: center.x + offset.width - size.width * scale / 2, y: center.y + offset.height - size.height * scale / 2,
                          width: size.width * scale, height: size.height * scale)
        let isOpen = peek.phase == .open && !expanded
        let chrome = showsChrome && isOpen ? max(0, 1 - abs(pinch) * 8) : 0
        return ZStack(alignment: .topLeading) {
            BrowserContentView(page: peek.page)
                .frame(width: size.width, height: size.height)
                .clipShape(shape)
                // On a shape of its own: a shadow on the web view would render it offscreen on every frame.
                .background {
                    shape.fill(palette.canvas)
                        .shadow(color: .black.opacity((palette.scheme == .dark ? 0.55 : 0.28) * min(1, reveal * 2)), radius: 40, y: 16)
                }
                .scaleEffect(scale)
                .offset(offset)
                .opacity(opacity)
                .allowsHitTesting(isOpen)
            VStack(spacing: 8) {
                PeekButton(symbol: "xmark", title: String(localized: "Close Peek"), shortcut: .cancelAction) { browser.dismissPeek() }
                    .accessibilityIdentifier("peek.close")
                    .scaleEffect(0.6 + 0.4 * chrome)
                PeekButton(symbol: BrowserCommand.openPeekInTab.symbol, title: BrowserCommand.openPeekInTab.title,
                           shortcut: browser.shortcuts.shortcut(for: .openPeekInTab)) { browser.perform(.openPeekInTab) }
                    .accessibilityIdentifier("peek.openInTab")
                    .scaleEffect(0.6 + 0.4 * chrome)
                    .animation(reduceMotion ? nil : PeekMotion.chrome.delay(0.05), value: chrome)
            }
            .position(x: card.maxX + 10 + Self.buttonSize / 2, y: card.minY + Self.buttonSize + 4)
            .opacity(chrome)
            .allowsHitTesting(isOpen && showsChrome)
        }
    }

    /// As large as the page allows with room for the buttons beside it, the page's own proportions kept.
    private static func shownScale(in size: CGSize) -> CGFloat {
        guard size.width > 0, size.height > 0 else { return largestScale }
        return min(largestScale, 1 - 2 * margin.width / size.width, 1 - 2 * margin.height / size.height)
    }

    /// Follows a pinch on the open preview; returns whether it took the event from the pages.
    private func followPinch(_ event: NSEvent) -> Bool {
        if event.phase == .began {
            guard browser.window.peek?.phase == .open, !browser.window.peekExpanded else { return false }
            pinching = true
            pinch = 0
            pinchSpeed = 0
            pinchTime = event.timestamp
            return true
        }
        guard pinching else { return false }
        let isOpen = browser.window.peek?.phase == .open
        switch event.phase {
        case .changed:
            guard isOpen else { break }
            pinch = min(max(pinch + event.magnification, -0.6), Self.spreadToFill * 1.5)
            let elapsed = event.timestamp - pinchTime
            if elapsed > 0 { pinchSpeed = event.magnification / elapsed }
            pinchTime = event.timestamp
            // Far enough commits at once, as the fingers still move.
            if pinch >= Self.spreadToOpen { commitPinch(opening: true) }
            else if pinch <= -Self.pinchToClose { commitPinch(opening: false) }
        case .ended, .cancelled:
            pinching = false
            guard isOpen else { break }
            if pinchSpeed > Self.flickSpeed, pinch > 0 { commitPinch(opening: true) }
            else if pinchSpeed < -Self.flickSpeed, pinch < 0 { commitPinch(opening: false) }
            else { move(with: PeekMotion.settling) { pinch = 0 } then: {} }
        default: break
        }
        return true
    }

    private func commitPinch(opening: Bool) {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        if opening { browser.openPeekInTab() } else { browser.dismissPeek() }
    }

    private func move(with animation: Animation, _ change: () -> Void, then completion: @escaping () -> Void) {
        guard !reduceMotion else {
            change()
            completion()
            return
        }
        withAnimation(animation, completionCriteria: .logicallyComplete, change) { completion() }
    }
}

/// The trackpad's pinches while a preview shows, before the pages zoom with them.
@MainActor
private final class PinchMonitor {
    private var monitor: Any?

    func start(_ handler: @escaping (NSEvent) -> Bool) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { handler($0) ? nil : $0 }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    isolated deinit { stop() }
}

/// A round glass button beside the preview.
private struct PeekButton: View {
    let symbol: String
    let title: String
    let shortcut: KeyboardShortcut?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(BrowserDesign.Typography.label)
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .buttonStyle(QuietButtonStyle(radius: 15))
        .browserGlass(.control, radius: 15)
        .tooltip(Text(verbatim: title), shortcut: shortcut)
        .accessibilityLabel(Text(verbatim: title))
    }
}
