import AppKit
import BrowserWebKit
import SwiftUI

/// Keeps recently shown web views attached to this window at their last valid size. This cache owns only
/// presentation: the registry still owns loading, hibernation and disposal. No snapshots or extra pages are made.
struct WebPageDeck: NSViewRepresentable {
    struct Pane {
        let id: UUID
        let page: BrowserPage
        let frame: CGRect
        let rendered: Bool
        var isMoving = false
    }

    let panes: [Pane]
    let selected: UUID?

    func makeNSView(context: Context) -> DeckView { DeckView() }
    func updateNSView(_ view: DeckView, context: Context) { view.show(panes, selected: selected) }

    final class DeckView: NSView {
        private static let limit = 8
        private var surfaces: [UUID: WebPageSurface] = [:]
        private var recent: [UUID] = []
        private var selected: UUID?
        private var needsPageFocus = false
        override var isFlipped: Bool { true }

        func show(_ panes: [Pane], selected: UUID?) {
            if self.selected != selected {
                self.selected = selected
                needsPageFocus = selected != nil
            }
            let shown = Set(panes.map(\.id))
            // A closed/hibernated page removes its web view itself; do not keep that page alive here.
            for (id, surface) in surfaces where surface.page == nil || surface.wasDetached {
                surface.removeFromSuperview()
                surfaces[id] = nil
                recent.removeAll { $0 == id }
            }
            for (id, surface) in surfaces where !shown.contains(id) {
                surface.isHidden = true
                surface.setAccessibilityHidden(true)
            }
            for pane in panes where pane.frame.width > 0 && pane.frame.height > 0 {
                let surface = surfaces[pane.id] ?? WebPageSurface()
                if surface.page !== pane.page { surface.claim(pane.page) }
                // Set a real size before attachment. Tab switches never animate or pass through a zero viewport.
                if surface.frame != pane.frame { surface.frame = pane.frame }
                surface.alphaValue = pane.rendered ? (pane.isMoving ? 0.55 : 1) : 0
                // A dragged pane steps back visually without changing the webpage's viewport.
                let scale: CGFloat = pane.isMoving ? 0.97 : 1
                let transform = CATransform3DMakeAffineTransform(CGAffineTransform(
                    a: scale, b: 0, c: 0, d: scale,
                    tx: surface.bounds.width * (1 - scale) / 2, ty: surface.bounds.height * (1 - scale) / 2))
                if let layer = surface.layer, !CATransform3DEqualToTransform(layer.sublayerTransform, transform) {
                    layer.sublayerTransform = transform
                }
                if surface.superview !== self { addSubview(surface) }
                surface.isHidden = false
                surface.setAccessibilityHidden(false)
                surface.layoutSubtreeIfNeeded()
                surfaces[pane.id] = surface
                recent.removeAll { $0 == pane.id }
                recent.append(pane.id)
            }
            while recent.count > Self.limit, let oldest = recent.first(where: { !shown.contains($0) }) {
                recent.removeAll { $0 == oldest }
                surfaces.removeValue(forKey: oldest)?.removeFromSuperview()
            }
            focusPageIfNeeded()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            focusPageIfNeeded()
        }

        private func focusPageIfNeeded() {
            guard needsPageFocus, let selected, let page = surfaces[selected]?.page,
                  let window, page.webView.window === window else { return }
            needsPageFocus = false
            window.makeFirstResponder(page.webView)
        }

        // Blank areas belong to native/internal panes and the SwiftUI chrome above this layer.
        override func hitTest(_ point: NSPoint) -> NSView? {
            let hit = super.hitTest(point)
            return hit === self ? nil : hit
        }
    }
}

/// The latest claimant owns a page: an outgoing Peek cannot steal the view back after adoption into a tab.
final class WebPageSurface: NSView {
    private static let owners = NSMapTable<BrowserPage, WebPageSurface>.weakToWeakObjects()
    private(set) weak var page: BrowserPage?
    private var attached = false
    var wasDetached: Bool { attached && page?.webView.superview !== self }
    override var isFlipped: Bool { true }

    func claim(_ page: BrowserPage) {
        subviews.forEach { $0.removeFromSuperview() }
        self.page = page
        attached = false
        Self.owners.setObject(self, forKey: page)
        wantsLayer = true
        layer?.cornerRadius = BrowserDesign.Radius.page
        layer?.masksToBounds = true
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0, let page, Self.owners.object(forKey: page) === self else { return }
        let view = page.webView
        if view.superview !== self {
            view.removeFromSuperview()
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
            attached = true
        } else if view.frame != bounds {
            view.frame = bounds
        }
    }
}
