import AppKit
import SwiftUI

/// AppKit's standard controls, hosted in our header with explicit public window actions.
/// The window's original titlebar buttons stay hidden and are never reparented.
struct NativeWindowControls: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ControlsView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ControlsView: NSView {
        private var buttons: [NSButton] = []

        override init(frame: NSRect) {
            super.init(frame: frame)
            let types: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
            let identifiers = ["window.close", "window.minimize", "window.fullScreen"]
            for (index, type) in types.enumerated() {
                guard let button = NSWindow.standardWindowButton(type, for: [.titled, .closable, .miniaturizable, .resizable]) else { continue }
                button.target = self
                button.tag = index
                button.action = #selector(performWindowAction(_:))
                button.setAccessibilityIdentifier(identifiers[index])
                addSubview(button)
                buttons.append(button)
            }
        }

        required init?(coder: NSCoder) { nil }

        override func layout() {
            super.layout()
            for (index, button) in buttons.enumerated() {
                button.setFrameOrigin(NSPoint(
                    x: 26 - button.frame.width / 2 + CGFloat(index) * 23,
                    y: (bounds.height - button.frame.height) / 2
                ))
            }
        }

        @objc private func performWindowAction(_ sender: NSButton) {
            switch sender.tag {
            case 0: window?.performClose(sender)
            case 1: window?.performMiniaturize(sender)
            default:
                if NSApp.currentEvent?.modifierFlags.contains(.option) == true { window?.performZoom(sender) }
                else { window?.toggleFullScreen(sender) }
            }
        }
    }
}
