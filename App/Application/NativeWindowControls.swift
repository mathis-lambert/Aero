import AppKit
import SwiftUI

/// The window's own close, minimize and full-screen button group, shown in our header. Only AppKit's group gives the
/// buttons their shared hover symbols and inactive-window look, so it is moved rather than recreated; AppKit gets it
/// back around full-screen transitions, which rebuild the titlebar. This object is the group's one owner.
@MainActor
final class WindowControls {
    private static let identifiers = ["window.close", "window.minimize", "window.fullScreen"]
    private static let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]

    private weak var window: NSWindow?
    /// Headers showing the controls, oldest first; the latest one holds the group.
    private var slots: [Weak] = []
    private weak var titlebar: NSView?
    private var titlebarFrame = NSRect.zero
    private var isChangingFullScreen = false
    private var observers: [NSObjectProtocol] = []

    private struct Weak { weak var view: NSView? }

    isolated deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    /// Move only a common container of all three native buttons, excluding the window's content view.
    private var group: NSView? {
        guard let window else { return nil }
        let buttons = Self.types.compactMap { window.standardWindowButton($0) }
        guard buttons.count == Self.types.count, let parent = buttons.first?.superview,
              parent !== window.contentView,
              buttons.allSatisfy({ $0.superview === parent }) else { return nil }
        return parent
    }
    private var slot: NSView? { slots.last { $0.view?.window === window }?.view }

    func attach(to window: NSWindow) {
        guard self.window !== window else { return }
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        observers.removeAll()
        titlebar = nil
        isChangingFullScreen = false
        self.window = window
        for name in [NSWindow.willEnterFullScreenNotification, NSWindow.willExitFullScreenNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isChangingFullScreen = true; self?.place() }
            })
        }
        for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                // The titlebar was rebuilt: the group is found again there.
                MainActor.assumeIsolated { self?.isChangingFullScreen = false; self?.titlebar = nil; self?.place() }
            })
        }
        // AppKit lays out its titlebar while the window resizes, even while the group is in a header.
        observers.append(center.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.slot?.needsLayout = true }
        })
        place()
    }

    fileprivate func show(in slot: NSView) {
        slots.removeAll { $0.view == nil || $0.view === slot }
        slots.append(Weak(view: slot))
        place()
    }

    fileprivate func remove(_ slot: NSView) {
        slots.removeAll { $0.view == nil || $0.view === slot }
        place()
    }

    /// Into the latest header, or hidden in the titlebar when there is none or during a full-screen transition.
    private func place() {
        guard let group else { return }
        if titlebar == nil, !(group.superview is Slot) {
            titlebar = group.superview
            titlebarFrame = group.frame
            for (index, type) in Self.types.enumerated() { window?.standardWindowButton(type)?.setAccessibilityIdentifier(Self.identifiers[index]) }
        }
        if !isChangingFullScreen, let slot {
            if group.superview !== slot { slot.addSubview(group) }
            group.isHidden = false
            slot.needsLayout = true
        } else if let titlebar {
            if group.superview !== titlebar {
                group.frame = titlebarFrame
                titlebar.addSubview(group)
            }
            group.isHidden = true
        }
    }

    fileprivate func layout(_ slot: NSView) {
        guard let group, group.superview === slot else { return }
        group.frame = slot.bounds
        for (index, type) in Self.types.enumerated() {
            guard let button = window?.standardWindowButton(type) else { continue }
            button.setFrameOrigin(NSPoint(x: 26 - button.frame.width / 2 + CGFloat(index) * 23, y: (slot.bounds.height - button.frame.height) / 2))
        }
    }

    /// Where a header shows the controls.
    fileprivate final class Slot: NSView {
        let controls: WindowControls
        init(controls: WindowControls) {
            self.controls = controls
            super.init(frame: .zero)
        }
        required init?(coder: NSCoder) { nil }

        /// False once its header is going away.
        var isActive = true {
            didSet { if isActive != oldValue { update() } }
        }

        func leave() { isActive = false }

        private func update() {
            if isActive, window != nil { controls.show(in: self) } else { controls.remove(self) }
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil { controls.remove(self) }
            super.viewWillMove(toWindow: newWindow)
        }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            update()
        }
        override func layout() {
            super.layout()
            controls.layout(self)
        }
    }
}

extension EnvironmentValues {
    @Entry var windowControls: WindowControls?
}

/// A header's place for the window controls; the latest active one shown holds them.
struct NativeWindowControls: View {
    var isActive = true
    @Environment(\.windowControls) private var controls

    var body: some View {
        if let controls { Host(controls: controls, isActive: isActive) }
    }

    private struct Host: NSViewRepresentable {
        let controls: WindowControls
        let isActive: Bool
        func makeNSView(context: Context) -> NSView { WindowControls.Slot(controls: controls) }
        func updateNSView(_ view: NSView, context: Context) { (view as? WindowControls.Slot)?.isActive = isActive }
        /// SwiftUI can keep a removed view in the window for a while; this is when the header is really gone.
        static func dismantleNSView(_ view: NSView, coordinator: ()) { (view as? WindowControls.Slot)?.leave() }
    }
}
