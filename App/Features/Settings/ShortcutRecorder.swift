import AppKit
import SwiftUI

/// A first responder scoped to the selected command’s inline editor. No application-wide keyboard monitor. Escape,
/// which a shortcut cannot use, ends recording as it cancels elsewhere.
struct ShortcutRecorder: NSViewRepresentable {
    let record: (NSEvent) -> Void
    let cancel: () -> Void

    func makeNSView(context: Context) -> RecorderView { RecorderView() }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.record = record
        view.cancel = cancel
    }

    final class RecorderView: NSView {
        var record: ((NSEvent) -> Void)?
        var cancel: (() -> Void)?
        override var acceptsFirstResponder: Bool { true }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            window?.makeFirstResponder(self)
        }
        override func keyDown(with event: NSEvent) { receive(event) }
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self else { return false }
            receive(event)
            return true
        }

        private func receive(_ event: NSEvent) {
            if event.charactersIgnoringModifiers == "\u{1B}" { cancel?() } else { record?(event) }
        }
    }
}
