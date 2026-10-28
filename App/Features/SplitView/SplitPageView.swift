import AppKit
import BrowserCore
import BrowserWebKit
import SwiftUI

/// The selected tab's page, alone or with the other panes of its split (docs/SPLIT_VIEW.md), each on a page surface of
/// its own, the gap between them a divider to drag, with a New Tab pane beside the selected tab while one is asked for.
/// A tab alone is a layout of one pane, so a pane coming beside it or going moves the same page rather than another
/// view. In a split, the focused pane, the selected tab or the New Tab pane, is ringed in the space's color; the page's
/// own controls act on it. A pane comes in from the trailing side and goes shrinking away; the others take their places
/// with a spring as panes come, go and resize, except under the pointer, which they follow; showing other tabs
/// altogether is immediate (`BrowserWindowState.paneGroup`). A pane taken by its grip moves to the side of another
/// it is dropped on, a pane of glass showing where until then.
struct SplitPageView: View {
    static let gap = BrowserDesign.pageInset
    /// The panes' coordinate space, which dragged dividers and grips report in.
    static let space = "split"
    /// A little longer than the shell's own motion: a page coming or going travels further.
    private static let motion = Animation.spring(duration: 0.42, bounce: 0.12)

    let browser: BrowserModel
    /// The panes as they show (`BrowserModel.paneLayout`).
    let layout: SplitNode
    /// A divider being dragged and where it is; the session takes the boundary when the drag ends.
    @State private var resizing: (divider: SplitDivider.Place, boundary: Double)?
    /// A pane taken by its grip, and where it would go.
    @State private var moving: (pane: UUID, destination: SplitDestination?)?
    @Environment(\.browserReduceMotion) private var reduceMotion

    var body: some View {
        let newPane = browser.window.newPane
        let inSplit = layout.tabIDs.count > 1
        // While a New Tab pane stands in the layout, its dividers are not the split's own.
        let split = newPane == nil ? browser.currentSplit : nil
        GeometryReader { area in
            let bounds = CGRect(origin: .zero, size: area.size)
            let root = resizing.map { layout.resizing($0.divider, to: $0.boundary) } ?? layout
            let frames = root.frames(in: bounds, gap: Self.gap)
            ZStack(alignment: .topLeading) {
                ForEach(layout.tabIDs, id: \.self) { id in
                    if let frame = frames[id] {
                        Group {
                            if let newPane, newPane.id == id {
                                NewTabPane(browser: browser)
                            } else if let tab = browser.session.tabs.first(where: { $0.id == id }) {
                                SplitPane(browser: browser, tab: tab, isFocused: newPane == nil && browser.window.selectedTabID == id,
                                          inSplit: inSplit, isMoving: moving?.pane == id) { point in
                                    move(id, to: point, in: bounds)
                                } onMoveEnd: {
                                    endMove()
                                }
                            }
                        }
                        .frame(width: frame.width, height: frame.height)
                        .offset(x: frame.minX, y: frame.minY)
                        .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                                removal: .scale(scale: 0.9).combined(with: .opacity)))
                    }
                }
                if let split, moving == nil {
                    ForEach(root.dividers(in: bounds, gap: Self.gap), id: \.place) { divider in
                        SplitDividerHandle(divider: divider) { boundary in
                            resizing = (divider.place, boundary)
                        } onEnd: { boundary in
                            browser.resizeSplit(split.id, divider: divider.place, to: boundary)
                            resizing = nil
                        } onReset: {
                            browser.equalizeSplit(split.id)
                        }
                    }
                }
                if let moving, let destination = moving.destination,
                   let frame = layout.removing(moving.pane)?.inserting(moving.pane, beside: destination.pane, at: destination.edge)?
                       .frames(in: bounds, gap: Self.gap)[moving.pane] {
                    PaneDropZone(browser: browser, frame: frame, symbol: "rectangle.2.swap")
                }
            }
            .animation(resizing == nil && !reduceMotion ? Self.motion : nil, value: root)
            .animation(reduceMotion ? nil : BrowserDesign.motion, value: moving?.destination)
        }
        .coordinateSpace(.named(Self.space))
        .background(PaneFocusTracker(browser: browser, panes: layout.tabIDs))
    }

    /// The side of another pane under `point`; over the moving pane itself, or a gap, nowhere.
    private func move(_ pane: UUID, to point: CGPoint, in bounds: CGRect) {
        let destination = layout.destination(at: point, in: bounds, gap: Self.gap).flatMap { $0.pane == pane ? nil : $0 }
        if destination != moving?.destination, destination != nil {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        moving = (pane, destination)
    }

    private func endMove() {
        defer { moving = nil }
        guard let moving, let destination = moving.destination else { return }
        browser.splitTab(moving.pane, beside: destination.pane, at: destination.edge)
    }
}

/// A New Tab page in a pane, its field focused: what it opens takes the pane's place. Escape on the empty field, or its
/// button, dismisses it.
private struct NewTabPane: View {
    let browser: BrowserModel
    @Environment(\.palette) private var palette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: BrowserDesign.Radius.page, style: .continuous)
        NewTabView(browser: browser, target: .newPane)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .browserSurface(fill: palette.canvas, border: palette.line, radius: BrowserDesign.Radius.page)
            .background { shape.fill(palette.canvas).pageShadow(palette.scheme) }
            .overlay { shape.strokeBorder(browser.accent.light(in: palette.scheme).opacity(0.85), lineWidth: 2).allowsHitTesting(false) }
            .overlay(alignment: .topTrailing) {
                IconButton(symbol: "xmark", label: "Close Pane", size: 28, radius: 14) { browser.cancelNewPane() }
                    .browserGlass(.control, radius: 14)
                    .padding(10)
                    .accessibilityIdentifier("split.newPane.close")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("split.newPane")
    }
}

/// One pane: its tab's page on a surface of its own. In a split, the pointer pushed against its top edge brings out a
/// glass capsule that names it and offers to take it out of the split or close it; the page's own top bar keeps its
/// clicks otherwise.
private struct SplitPane: View {
    /// How close to the top edge the pointer must come: the very edge, as for the page's corner actions.
    private static let chromeReach: CGFloat = 6
    /// How long the capsule stays once the pointer has left it.
    private static let chromeGrace = Duration.milliseconds(450)

    let browser: BrowserModel
    let tab: BrowserTab
    /// The page's own controls act on it.
    let isFocused: Bool
    /// Beside other panes: it is ringed when focused, and has its capsule.
    let inSplit: Bool
    /// Taken by its grip: it steps back, its capsule staying.
    let isMoving: Bool
    /// Where its grip is, in the split's space, as it is dragged; and when it is let go.
    let onMove: (CGPoint) -> Void
    let onMoveEnd: () -> Void
    @State private var showsChrome = false
    @State private var overChrome = false
    @State private var hidingChrome: Task<Void, Never>?
    @Environment(\.palette) private var palette
    @Environment(\.browserReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: BrowserDesign.Radius.page, style: .continuous)
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Under a link's preview, what every pane shows blurs, as a page does.
            .peekBackdrop(browser)
            .browserSurface(fill: palette.canvas, border: palette.line, radius: BrowserDesign.Radius.page)
            // On a shape of its own: a shadow on the web view would render it offscreen on every frame.
            .background { shape.fill(palette.canvas).pageShadow(palette.scheme) }
            .scaleEffect(isMoving ? 0.97 : 1)
            .opacity(isMoving ? 0.55 : 1)
            .animation(reduceMotion ? nil : BrowserDesign.motion, value: isMoving)
            .overlay {
                if isFocused, inSplit, !isMoving {
                    shape.strokeBorder(browser.accent.light(in: palette.scheme).opacity(0.85), lineWidth: 2)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .top) {
                if showsChrome || isMoving, inSplit {
                    PaneChrome(browser: browser, tab: tab, onMove: onMove, onMoveEnd: onMoveEnd)
                        .padding(.top, 8)
                        .onHover { hovering in
                            overChrome = hovering
                            if hovering { hidingChrome?.cancel() } else { hideChromeSoon() }
                        }
                        .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
                }
            }
            // Hovering never takes a click from the page.
            .onContinuousHover { phase in
                guard inSplit, case .active(let point) = phase, point.y <= Self.chromeReach else { return }
                hidingChrome?.cancel()
                if !showsChrome { withAnimation(reduceMotion ? nil : BrowserDesign.motion) { showsChrome = true } }
                // Brought out by a pass of the pointer, it goes if the pointer does not come onto it.
                hideChromeSoon()
            }
            .animation(reduceMotion ? nil : BrowserDesign.hover, value: isFocused && inSplit)
            // Focused from the keyboard or the sidebar, the pane takes the keyboard too.
            .onChange(of: isFocused) { _, focused in
                guard focused else { return }
                let view: NSView? = browser.pages.livePage(tab.id)?.webView ?? browser.terminals.existing(tab.id)?.view
                if let view, let window = view.window, !(window.firstResponder.map { ($0 as? NSView)?.isDescendant(of: view) == true } ?? false) {
                    window.makeFirstResponder(view)
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(verbatim: tab.displayTitle))
            .accessibilityAddTraits(isFocused ? .isSelected : [])
            .accessibilityIdentifier("split.pane")
    }

    private func hideChromeSoon() {
        hidingChrome?.cancel()
        hidingChrome = Task {
            do { try await Task.sleep(for: Self.chromeGrace) } catch { return }
            if !overChrome { withAnimation(reduceMotion ? nil : BrowserDesign.motion) { showsChrome = false } }
        }
    }

    @ViewBuilder private var content: some View {
        if let page = InternalPage(url: tab.url) {
            // A native page takes the focus with a click, as no web view reports it.
            InternalPageView(page: page, tab: tab, browser: browser)
                .simultaneousGesture(TapGesture().onEnded { if !isFocused { browser.selectTab(tab.id) } })
        } else if let page = browser.pages.livePage(tab.id) {
            BrowserContentView(page: page).pageFloats(browser, page: page, isFocused: isFocused)
        } else {
            palette.canvas
        }
    }
}

/// The pane's grip, name and two actions, on glass. Dragging the grip moves the pane to the side of another.
private struct PaneChrome: View {
    let browser: BrowserModel
    let tab: BrowserTab
    let onMove: (CGPoint) -> Void
    let onMoveEnd: () -> Void
    @State private var dragging = false
    @State private var overGrip = false
    @Environment(\.palette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            // The system's sign of something to reorder by dragging.
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(dragging || overGrip ? palette.ink : palette.secondary)
                .frame(width: 22, height: 26)
                .contentShape(Rectangle())
                .onHover { overGrip = $0 }
                .paneDrag(cursor: dragging ? .closedHand : .openHand) { point in
                    dragging = true
                    onMove(point)
                } onEnded: { _ in
                    dragging = false
                    onMoveEnd()
                }
                .tooltip(String(localized: "Move Pane"))
                .accessibilityLabel(Text("Move Pane"))
                .accessibilityIdentifier("split.pane.grip")
            FaviconView(cache: browser.favicons, key: browser.faviconKey(for: tab), size: 14) {
                Image(systemName: InternalPage(url: tab.url)?.symbol ?? "globe").font(BrowserDesign.Typography.caption).foregroundStyle(.secondary)
            }
            Text(verbatim: tab.displayTitle)
                .font(BrowserDesign.Typography.label)
                .lineLimit(1)
                .frame(maxWidth: 220, alignment: .leading)
            IconButton(symbol: "rectangle.portrait.and.arrow.right", label: "Move Out of Split View", size: 24, radius: 12) {
                browser.removeFromSplit(tab.id)
            }
            .accessibilityIdentifier("split.pane.moveOut")
            IconButton(symbol: "xmark", label: "Close Tab", size: 24, radius: 12) { browser.closeTab(tab.id) }
                .accessibilityIdentifier("split.pane.close")
        }
        .padding(.horizontal, 4)
        .frame(height: 32)
        .browserGlass(.panel, radius: 16)
    }
}

/// The gap between two parts of a split, a divider under the pointer: dragging it resizes them, a double click shares
/// the space equally. A glass grip shows where it is while the pointer is over it.
private struct SplitDividerHandle: View {
    /// Wider than the gap, so the divider is easy to take.
    private static let reach: CGFloat = 5

    let divider: SplitDivider
    let onChange: (Double) -> Void
    let onEnd: (Double) -> Void
    let onReset: () -> Void
    @State private var hovered = false
    @State private var dragging = false
    @Environment(\.browserReduceMotion) private var reduceMotion

    var body: some View {
        let horizontal = divider.axis == .horizontal
        let area = divider.line.insetBy(dx: horizontal ? -Self.reach : 0, dy: horizontal ? 0 : -Self.reach)
        Color.clear
            .contentShape(Rectangle())
            .overlay {
                Capsule()
                    .fill(.clear)
                    .browserGlass(.control, radius: 3)
                    .frame(width: horizontal ? 5 : 44, height: horizontal ? 44 : 5)
                    .scaleEffect(dragging ? 1.15 : 1)
                    .opacity(hovered || dragging ? 1 : 0)
            }
            .frame(width: area.width, height: area.height)
            .onHover { hovered = $0 }
            .paneDrag(cursor: horizontal ? .resizeLeftRight : .resizeUpDown) { point in
                dragging = true
                onChange(divider.boundary(at: point, gap: SplitPageView.gap))
            } onEnded: { point in
                dragging = false
                onEnd(divider.boundary(at: point, gap: SplitPageView.gap))
            } onDoubleClick: {
                onReset()
            }
            .offset(x: area.minX, y: area.minY)
            .animation(reduceMotion ? nil : BrowserDesign.hover, value: hovered || dragging)
            .accessibilityHidden(true)
    }
}

/// Follows the window's keyboard focus into the panes: the pane whose page or terminal takes it becomes the selected
/// tab, so a click anywhere in a pane focuses it without taking the click from the page.
private struct PaneFocusTracker: NSViewRepresentable {
    let browser: BrowserModel
    let panes: [UUID]

    func makeNSView(context: Context) -> TrackerView { TrackerView() }

    func updateNSView(_ view: TrackerView, context: Context) {
        let browser = browser, panes = panes
        view.onResponder = { responder in
            guard let responder = responder as? NSView else { return }
            let pane = panes.first { id in
                let shown: NSView? = browser.pages.livePage(id)?.webView ?? browser.terminals.existing(id)?.view
                return shown.map { responder === $0 || responder.isDescendant(of: $0) } ?? false
            }
            if let pane, browser.window.selectedTabID != pane { browser.selectTab(pane) }
        }
    }

    final class TrackerView: NSView {
        var onResponder: (NSResponder?) -> Void = { _ in }
        private var observation: NSKeyValueObservation?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            observation = window?.observe(\.firstResponder, options: [.new]) { [weak self] window, _ in
                MainActor.assumeIsolated { self?.onResponder(window.firstResponder) }
            }
        }
    }
}

extension View {
    /// Takes the pointer's drags over the view in AppKit, so one near the window's top edge never moves the window,
    /// and reports where the pointer is in the panes' space (`SplitPageView.space`).
    fileprivate func paneDrag(cursor: NSCursor, onChanged: @escaping (CGPoint) -> Void, onEnded: @escaping (CGPoint) -> Void,
                              onDoubleClick: (() -> Void)? = nil) -> some View {
        modifier(PaneDrag(cursor: cursor, onChanged: onChanged, onEnded: onEnded, onDoubleClick: onDoubleClick))
    }
}

private struct PaneDrag: ViewModifier {
    let cursor: NSCursor
    let onChanged: (CGPoint) -> Void
    let onEnded: (CGPoint) -> Void
    let onDoubleClick: (() -> Void)?
    /// The view's frame in the panes' space; a drag reads it as it begins, since the view may move under the pointer.
    @State private var frame = CGRect.zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(SplitPageView.space)) } action: { frame = $0 }
            .overlay {
                DragView(cursor: cursor, origin: { frame.origin }, onChanged: onChanged, onEnded: onEnded, onDoubleClick: onDoubleClick)
            }
    }

    private struct DragView: NSViewRepresentable {
        let cursor: NSCursor
        let origin: () -> CGPoint
        let onChanged: (CGPoint) -> Void
        let onEnded: (CGPoint) -> Void
        let onDoubleClick: (() -> Void)?

        func makeNSView(context: Context) -> TrackingView { TrackingView() }

        func updateNSView(_ view: TrackingView, context: Context) {
            view.drag = self
            view.window?.invalidateCursorRects(for: view)
        }

        final class TrackingView: NSView {
            var drag: DragView?
            /// Where the pointer went down, in the panes' space and in the window.
            private var start: (point: CGPoint, window: CGPoint)?
            /// A click that never moved ends nothing.
            private var dragged = false

            override var isFlipped: Bool { true }
            override var mouseDownCanMoveWindow: Bool { false }
            override func resetCursorRects() { if let drag { addCursorRect(bounds, cursor: drag.cursor) } }

            override func mouseDown(with event: NSEvent) {
                guard let drag else { return }
                if event.clickCount == 2, let onDoubleClick = drag.onDoubleClick { onDoubleClick(); return }
                let local = convert(event.locationInWindow, from: nil)
                let origin = drag.origin()
                start = (CGPoint(x: origin.x + local.x, y: origin.y + local.y), event.locationInWindow)
                dragged = false
            }

            override func mouseDragged(with event: NSEvent) {
                guard let point = point(of: event) else { return }
                dragged = true
                drag?.onChanged(point)
            }

            override func mouseUp(with event: NSEvent) {
                defer { start = nil }
                if dragged, let point = point(of: event) { drag?.onEnded(point) }
            }

            /// The window's coordinates rise upward; the panes' space runs downward.
            private func point(of event: NSEvent) -> CGPoint? {
                guard let start else { return nil }
                return CGPoint(x: start.point.x + event.locationInWindow.x - start.window.x,
                               y: start.point.y - (event.locationInWindow.y - start.window.y))
            }
        }
    }
}
