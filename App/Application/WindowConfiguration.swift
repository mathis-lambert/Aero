import AppKit
import SwiftUI

/// Gives the browser window a full-height content view and hides its titlebar buttons, which
/// `NativeWindowControls` replaces in the sidebar, while AppKit keeps window behavior.
struct WindowConfiguration: NSViewRepresentable {
    static let mainWindowIdentifier = "aero.main"

    static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == mainWindowIdentifier }
    }

    func makeNSView(context: Context) -> NSView { WindowProbe() }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? WindowProbe)?.hideTitlebarButtons()
    }

    private final class WindowProbe: NSView {
        override func viewWillMove(toWindow newWindow: NSWindow?) {
            NotificationCenter.default.removeObserver(self)
            super.viewWillMove(toWindow: newWindow)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.identifier = NSUserInterfaceItemIdentifier(WindowConfiguration.mainWindowIdentifier)
            window.styleMask.insert(.fullSizeContentView)
            window.titleVisibility = .hidden
            window.backgroundColor = .windowBackgroundColor
            window.isMovableByWindowBackground = false
            // An empty native toolbar would cover the sidebar and page content.
            window.toolbar = nil
            // Full screen rebuilds the titlebar, which shows its buttons again.
            for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(hideTitlebarButtons), name: name, object: window)
            }
            hideTitlebarButtons()
        }

        @objc func hideTitlebarButtons() {
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(type)?.isHidden = true
            }
        }
    }
}
