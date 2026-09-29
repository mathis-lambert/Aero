import AppKit
import SwiftUI

/// Gives the browser window a full-height content view and a transparent titlebar, and hands it to the window
/// controls' owner (`WindowControls`), while AppKit keeps window behavior.
struct WindowConfiguration: NSViewRepresentable {
    let controls: WindowControls

    static let mainWindowIdentifier = "aero.main"

    static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == mainWindowIdentifier }
    }

    func makeNSView(context: Context) -> NSView { WindowProbe(controls: controls) }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class WindowProbe: NSView {
        let controls: WindowControls
        init(controls: WindowControls) {
            self.controls = controls
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
            window.identifier = NSUserInterfaceItemIdentifier(WindowConfiguration.mainWindowIdentifier)
            window.styleMask.insert(.fullSizeContentView)
            window.titleVisibility = .hidden
            window.backgroundColor = .windowBackgroundColor
            window.isMovableByWindowBackground = false
            // An empty native toolbar would cover the sidebar and page content.
            window.toolbar = nil
            // Full screen rebuilds the titlebar.
            for name in [NSWindow.didEnterFullScreenNotification, NSWindow.didExitFullScreenNotification] {
                NotificationCenter.default.addObserver(self, selector: #selector(styleTitlebar), name: name, object: window)
            }
            styleTitlebar()
            controls.attach(to: window)
        }

        @objc private func styleTitlebar() {
            window?.titlebarAppearsTransparent = true
            window?.titlebarSeparatorStyle = .none
        }
    }
}
