import AppKit
import BrowserWebKit
import SwiftUI

/// A page in a window of its own, outside the browser window: its site and connection, then the page. Used by
/// sign-ins for other apps and by websites' popup windows.
struct SiteWindowContent<Accessory: View>: View {
    let page: BrowserPage
    @ViewBuilder var accessory: Accessory
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: page.isSecure ? "lock.fill" : "globe")
                    .foregroundStyle(palette.secondary)
                    .accessibilityLabel(page.isSecure ? Text("Secure connection") : Text("Website"))
                Text(verbatim: page.webView.url?.host() ?? "")
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                accessory
            }
            // The window's own controls sit at the leading edge.
            .padding(.leading, 80)
            .padding(.trailing, 12)
            .frame(height: 40)
            Divider()
            BrowserContentView(page: page)
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(palette.canvas)
        .accessibilityElement(children: .contain)
    }
}

/// A website's `window.open` with a size, as a window of its own sized as asked (docs/BROWSING.md › Popups). Its
/// dialogs ask in it; `window.close()` or closing the window ends its page.
@MainActor
final class PopupWindow: NSObject, NSWindowDelegate {
    private static let defaultSize = CGSize(width: 520, height: 640)
    private static let minimumSize = CGSize(width: 240, height: 200)

    let page: BrowserPage
    let profileID: UUID
    private let dialogs = PopupDialogs()
    private let window: NSWindow
    private let onEnd: (PopupWindow) -> Void
    private let discard: (BrowserPage) -> Void
    private var hasEnded = false

    init(page: BrowserPage, profileID: UUID, contentSize: CGSize, over parent: NSWindow?, discard: @escaping (BrowserPage) -> Void,
         onEnd: @escaping (PopupWindow) -> Void) {
        self.page = page
        self.profileID = profileID
        self.discard = discard
        self.onEnd = onEnd
        let screen = parent?.screen?.visibleFrame.size ?? NSScreen.main?.visibleFrame.size ?? Self.defaultSize
        let width = contentSize.width.isFinite && contentSize.width > 0 ? contentSize.width : Self.defaultSize.width
        let height = contentSize.height.isFinite && contentSize.height > 0 ? contentSize.height : Self.defaultSize.height
        let size = CGSize(width: min(max(width, Self.minimumSize.width), max(screen.width, Self.minimumSize.width)),
                          height: min(max(height, Self.minimumSize.height), max(screen.height - 40, Self.minimumSize.height)) + 40)
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        super.init()
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentMinSize = Self.minimumSize
        window.contentView = NSHostingView(rootView: PopupWindowView(page: page, dialogs: dialogs).browserMotionPreferences())
        window.delegate = self
        if let parent {
            window.setFrameOrigin(NSPoint(x: parent.frame.midX - window.frame.width / 2, y: parent.frame.midY - window.frame.height / 2))
        } else {
            window.center()
        }
        page.onClose = { [weak self] in self?.close() }
        page.onDialog = { [weak self] dialog in await self?.dialogs.ask(dialog) ?? .dismissed }
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard !hasEnded else { return }
        end()
        window.close()
    }

    private func end() {
        guard !hasEnded else { return }
        hasEnded = true
        dialogs.dismiss()
        window.delegate = nil
        discard(page)
        onEnd(self)
    }

    func windowWillClose(_ notification: Notification) { end() }
}

/// The popup's dialogs, one at a time, over its own page.
@MainActor @Observable
private final class PopupDialogs {
    var shown: PageDialogRequest?

    func ask(_ dialog: PageDialog) async -> PageDialogAnswer {
        dismiss()
        return await withCheckedContinuation { continuation in
            shown = PageDialogRequest(tabID: nil, dialog: dialog) { continuation.resume(returning: $0) }
        }
    }

    func answer(_ answer: PageDialogAnswer) {
        let request = shown
        shown = nil
        request?.answer(answer)
    }

    func dismiss() { answer(.dismissed) }
}

private struct PopupWindowView: View {
    let page: BrowserPage
    let dialogs: PopupDialogs

    var body: some View {
        SiteWindowContent(page: page) { Spacer(minLength: 8) }
            .accessibilityIdentifier("popupWindow")
            .prompt(dialogs.shown, onCancel: dialogs.dismiss) { request in
                PageDialogCard(dialog: request.dialog, answer: dialogs.answer)
            }
    }
}
