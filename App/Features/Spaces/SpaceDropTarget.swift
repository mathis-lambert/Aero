import AppKit
import BrowserCore
import SwiftUI
import UniformTypeIdentifiers

/// A space's icon in the footer takes tabs or a group dragged from the sidebar: resting on it opens the space, to
/// drop them at a place of its page, and dropping on it moves them to the end of their kind of place there. The drop is
/// AppKit's for the reason `SidebarDropTarget` gives.
struct SpaceDropTarget: NSViewRepresentable {
    let browser: BrowserModel
    let space: BrowserSpace
    @Binding var targeted: Bool

    func makeNSView(context: Context) -> DropView {
        let view = DropView()
        view.registerForDraggedTypes([NSPasteboard.PasteboardType(UTType.aeroTab.identifier)])
        return view
    }

    func updateNSView(_ view: DropView, context: Context) {
        let browser = browser, spaceID = space.id, targeted = $targeted
        view.accepts = { browser.window.tabDrag.map { $0.spaceID != spaceID } ?? false }
        view.onTarget = { targeted.wrappedValue = $0 }
        view.onRest = {
            guard browser.window.tabDrag != nil else { return }
            browser.switchSpace(spaceID)
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        view.onEnd = { browser.window.tabDrag = nil }
        view.onDrop = {
            guard let drag = browser.window.tabDrag, drag.spaceID != spaceID else { return false }
            browser.window.tabDrag = nil
            if drag.movesGroups { browser.movePinned(drag.items, toSpace: spaceID, before: nil, showing: drag.shownTabID) }
            else { browser.moveTabs(drag.tabIDs, toSpace: spaceID, showing: drag.shownTabID) }
            return true
        }
    }

    final class DropView: NSView {
        var accepts: () -> Bool = { false }
        var onTarget: (Bool) -> Void = { _ in }
        var onRest: () -> Void = {}
        var onDrop: () -> Bool = { false }
        var onEnd: () -> Void = {}
        private var rest: Task<Void, Never>?

        override func hitTest(_ point: NSPoint) -> NSView? {
            accepts() ? super.hitTest(point) : nil
        }

        override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
            guard accepts() else { return [] }
            onTarget(true)
            rest?.cancel()
            rest = Task { [weak self] in
                do { try await Task.sleep(for: TabDropLayout.edgeDelay) } catch { return }
                self?.onRest()
            }
            return .move
        }

        override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation { accepts() ? .move : [] }

        override func draggingExited(_ sender: (any NSDraggingInfo)?) { end() }

        override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool { accepts() }

        override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
            end()
            return onDrop()
        }

        override func draggingEnded(_ sender: any NSDraggingInfo) {
            end()
            onEnd()
        }

        private func end() {
            rest?.cancel()
            rest = nil
            onTarget(false)
        }

        isolated deinit { rest?.cancel() }
    }
}
