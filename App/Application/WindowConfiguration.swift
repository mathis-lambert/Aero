import AppKit
import SwiftUI

/// Gives the browser a full-height content view while AppKit keeps window behavior.
struct WindowConfiguration: NSViewRepresentable {
    static let mainWindowIdentifier = "aero.main"
    let identifier: String
    var usesBrowserChrome = false

    func makeNSView(context: Context) -> NSView {
        WindowProbe(identifier: identifier, usesBrowserChrome: usesBrowserChrome)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let probe = nsView as? WindowProbe else { return }
        probe.usesBrowserChrome = usesBrowserChrome
        probe.updateWindowControls()
    }

    private final class WindowProbe: NSView {
        let windowIdentifier: String
        var usesBrowserChrome: Bool

        init(identifier: String, usesBrowserChrome: Bool) {
            windowIdentifier = identifier
            self.usesBrowserChrome = usesBrowserChrome
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            NotificationCenter.default.removeObserver(self)
            super.viewWillMove(toWindow: newWindow)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.identifier = NSUserInterfaceItemIdentifier(windowIdentifier)
            window.styleMask.insert(.fullSizeContentView)
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.backgroundColor = .windowBackgroundColor
            window.isMovableByWindowBackground = false

            if usesBrowserChrome {
                // An empty native toolbar would cover the sidebar and page content.
                window.toolbar = nil
                for name in [NSWindow.didResizeNotification, NSWindow.didBecomeKeyNotification,
                             NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
                    NotificationCenter.default.addObserver(self, selector: #selector(updateWindowControls), name: name, object: window)
                }
            }
            updateWindowControls()
        }

        @objc func updateWindowControls() {
            guard usesBrowserChrome, let window else { return }
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(type)?.isHidden = true
            }
        }
    }
}
