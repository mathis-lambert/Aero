import AppKit
import BrowserCore
import SwiftUI
import UniformTypeIdentifiers

extension View {
    /// A tab dragged from the sidebar over the page shows where it would open beside the pane under it, at that pane's
    /// nearest side, and opens there when dropped (docs/SPLIT_VIEW.md).
    func splitDropZones(_ browser: BrowserModel) -> some View {
        modifier(SplitDropZones(browser: browser))
    }
}

private struct SplitDropZones: ViewModifier {
    /// Stands for the dropped tab in the layout the preview is drawn from.
    private static let placeholder = UUID()
    private static let motion = Animation.spring(response: 0.3, dampingFraction: 0.8)

    let browser: BrowserModel
    @State private var target: SplitDestination?
    @Environment(\.browserReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { area in
                let bounds = CGRect(origin: .zero, size: area.size)
                ZStack(alignment: .topLeading) {
                    if let target, let frame = preview(for: target, in: bounds) {
                        PaneDropZone(browser: browser, frame: frame, symbol: BrowserCommand.newPane.symbol)
                    }
                    PageDropTarget(accepts: { droppedTab != nil && layout != nil }) { point in
                        let next = self.target(at: point, in: bounds)
                        if next != target {
                            if next != nil { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
                            target = next
                        }
                    } onDrop: {
                        defer { target = nil }
                        guard let target, let tabID = droppedTab else { return false }
                        browser.window.tabDrag = nil
                        browser.splitTab(tabID, beside: target.pane, at: target.edge)
                        return true
                    } onEnd: {
                        target = nil
                    }
                }
                .animation(reduceMotion ? nil : Self.motion, value: target)
            }
        }
    }

    /// The first tab of a drag from the sidebar, if it may join the page's split.
    private var droppedTab: UUID? {
        guard browser.window.newPane == nil, let drag = browser.window.tabDrag, !drag.movesGroups, let tabID = drag.tabIDs.first,
              browser.session.split(containing: tabID) == nil, tabID != browser.window.selectedTabID,
              (browser.currentSplit?.tabIDs.count ?? 1) < TabSplit.maximumPanes else { return nil }
        return tabID
    }

    /// The page's layout, which has no New Tab pane while a tab can drop (`droppedTab`).
    private var layout: SplitNode? { browser.paneLayout }

    /// The pane under `point` and its side nearest to it; in a gap, where it was.
    private func target(at point: CGPoint, in bounds: CGRect) -> SplitDestination? {
        guard droppedTab != nil, let layout else { return nil }
        return layout.destination(at: point, in: bounds, gap: SplitPageView.gap) ?? target
    }

    private func preview(for target: SplitDestination, in bounds: CGRect) -> CGRect? {
        layout?.inserting(Self.placeholder, beside: target.pane, at: target.edge)?.frames(in: bounds, gap: SplitPageView.gap)[Self.placeholder]
    }
}

/// Where a pane would go, a tab dropped or a pane moved: a pane of glass in the space's color, its symbol in the middle.
struct PaneDropZone: View {
    let browser: BrowserModel
    let frame: CGRect
    let symbol: String
    @Environment(\.palette) private var palette

    var body: some View {
        let accent = browser.accent.light(in: palette.scheme)
        RoundedRectangle(cornerRadius: BrowserDesign.Radius.page, style: .continuous)
            .fill(accent.opacity(0.1))
            .browserGlass(.selection, tint: accent, radius: BrowserDesign.Radius.page)
            .overlay {
                RoundedRectangle(cornerRadius: BrowserDesign.Radius.page, style: .continuous).strokeBorder(accent.opacity(0.7), lineWidth: 2)
            }
            .overlay { Image(systemName: symbol).font(.system(size: 22, weight: .medium)).foregroundStyle(accent) }
            .frame(width: frame.width, height: frame.height)
            .offset(x: frame.minX, y: frame.minY)
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
            .accessibilityHidden(true)
    }
}

/// Takes tabs dragged from the sidebar over the page; AppKit's, as the sidebar's own drop is (`SidebarDropTarget`). It
/// lets everything else through, the page's own drops included.
private struct PageDropTarget: NSViewRepresentable {
    let accepts: () -> Bool
    let onMove: (CGPoint) -> Void
    let onDrop: () -> Bool
    let onEnd: () -> Void

    func makeNSView(context: Context) -> DropView {
        let view = DropView()
        view.registerForDraggedTypes([NSPasteboard.PasteboardType(UTType.aeroTab.identifier)])
        return view
    }

    func updateNSView(_ view: DropView, context: Context) {
        view.accepts = accepts
        view.onMove = onMove
        view.onDrop = onDrop
        view.onEnd = onEnd
    }

    final class DropView: NSView {
        var accepts: () -> Bool = { false }
        var onMove: (CGPoint) -> Void = { _ in }
        var onDrop: () -> Bool = { false }
        var onEnd: () -> Void = {}

        override var isFlipped: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? { accepts() ? super.hitTest(point) : nil }

        override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation { update(sender) }

        override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { update(sender) }

        override func draggingExited(_ sender: (any NSDraggingInfo)?) { onEnd() }

        override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { accepts() }

        override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool { onDrop() }

        override func draggingEnded(_ sender: any NSDraggingInfo) { onEnd() }

        private func update(_ sender: any NSDraggingInfo) -> NSDragOperation {
            guard accepts() else { return [] }
            onMove(convert(sender.draggingLocation, from: nil))
            return .move
        }
    }
}
