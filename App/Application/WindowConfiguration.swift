import AppKit
import SwiftUI

/// Names the browser window and hands it to the window controls' owner (`WindowControls`). Its full-height content
/// and hidden titlebar are the scene's `.hiddenTitleBar` style.
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

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.identifier = NSUserInterfaceItemIdentifier(WindowConfiguration.mainWindowIdentifier)
            controls.attach(to: window)
        }
    }
}
