import AppKit
import SwiftUI

/// A first responder scoped to the selected command’s inline editor. No application-wide keyboard monitor.
struct ShortcutRecorder: NSViewRepresentable {
    let record: (NSEvent) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.record = record
        return view
    }
    func updateNSView(_ view: RecorderView, context: Context) { view.record = record }

    final class RecorderView: NSView {
        var record: ((NSEvent) -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }
        override func keyDown(with event: NSEvent) { record?(event) }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self else { return false }
            record?(event)
            return true
        }
    }
}
