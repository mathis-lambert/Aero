import AppKit
import BrowserCore
import SwiftUI

extension View {
    /// Resting the pointer on a closed group lists its tabs beside it, to open one without opening the group. See
    /// docs/BROWSING.md › Favorites and open tabs.
    func folderPreview(browser: BrowserModel, groupID: UUID, enabled: Bool) -> some View {
        background(FolderPreviewAnchor(browser: browser, groupID: groupID, enabled: enabled))
    }
}

/// The preview's place: beside the header on its trailing side, or its leading side when there is no room, its top
/// level with the header's, always fully on screen.
enum FolderPreviewPlacement {
    static let gap: CGFloat = 8

    static func origin(beside anchor: CGRect, size: CGSize, screen: CGRect, rightToLeft: Bool) -> CGPoint {
        let trailing = rightToLeft ? anchor.minX - gap - size.width : anchor.maxX + gap
        let leading = rightToLeft ? anchor.maxX + gap : anchor.minX - gap - size.width
        let fits = { (x: CGFloat) in x >= screen.minX && x + size.width <= screen.maxX }
        let x = fits(trailing) ? trailing : fits(leading) ? leading : min(max(trailing, screen.minX), screen.maxX - size.width)
        // AppKit's screen coordinates grow upward: the top edge is the anchor's maxY.
        let y = min(max(anchor.maxY - size.height, screen.minY), screen.maxY - size.height)
        return CGPoint(x: x, y: y)
    }
}

/// The group's tabs as the sidebar shows them, with the sidebar's own rows: a click opens one, and each closes, or
/// leaves the favorites, from its row's button. The list follows the group, so a row leaves as its tab does.
private struct FolderPreviewList: View {
    private static let width: CGFloat = 240
    private static let visibleRows = 8
    /// Room around the card for its shadow, inside the panel; less than the gap to the header, so the panel never
    /// lies over it.
    static let margin: CGFloat = 8

    let browser: BrowserModel
    let groupID: UUID
    /// Ends the preview once a tab opens or the group has none left.
    let close: () -> Void
    /// Fits the panel to the rows left, once they have closed up.
    let refit: () -> Void
    @Namespace private var selection
    @State private var layout = TabDropLayout()
    @Environment(\.palette) private var palette

    var body: some View {
        let tabs = browser.session.tabs.filter { $0.place == .list(group: groupID) }
        let selectedTabID = browser.window.selectedTabID
        ScrollView {
            VStack(spacing: SidebarTabs.rowSpacing) {
                ForEach(tabs) { tab in
                    TabRow(browser: browser, tab: tab, selected: selectedTabID == tab.id, marked: false, lifted: false,
                           selection: selection, layout: layout)
                }
            }
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize)
        .frame(height: max(0, CGFloat(min(tabs.count, Self.visibleRows)) * (BrowserDesign.tabRowHeight + SidebarTabs.rowSpacing) - SidebarTabs.rowSpacing))
        .padding(6)
        .frame(width: Self.width)
        .browserSurface(fill: palette.sidebar, border: palette.line, radius: BrowserDesign.Radius.card)
        // A row leaving closes up as in the sidebar, the card with it, before the panel fits what is left.
        .browserAnimation(value: tabs.map(\.id))
        .shadow(color: .black.opacity(palette.scheme == .dark ? 0.4 : 0.16), radius: 6, y: 2)
        .padding(Self.margin)
        .frame(maxHeight: .infinity, alignment: .top)
        .onChange(of: selectedTabID) { close() }
        .onChange(of: tabs.map(\.id)) { _, ids in if ids.isEmpty { close() } else { refit() } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sidebar.folderPreview")
    }
}

/// Whether the preview is coming or going, for its card to grow out of the header and fade back into it.
@MainActor @Observable
private final class FolderPreviewPresence {
    var shown = false
    /// The header lies on the card's left on screen, whatever the layout direction.
    var headerOnLeft = true
}

/// The card grows a little out of the header's side as it comes, and shrinks back toward it as it goes. With Reduce
/// Motion it only fades.
private struct FolderPreviewEntrance: ViewModifier {
    private static let arrival = Animation.spring(duration: 0.24, bounce: 0.14)
    private static let departure = Animation.easeIn(duration: 0.12)

    let presence: FolderPreviewPresence
    @Environment(\.browserReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shown = presence.shown
        let moving = !shown && !reduceMotion
        content
            .scaleEffect(moving ? 0.94 : 1, anchor: UnitPoint(x: presence.headerOnLeft ? 0 : 1, y: 0))
            .offset(x: moving ? (presence.headerOnLeft ? -6 : 6) : 0)
            .opacity(shown ? 1 : 0)
            .animation(shown ? Self.arrival : Self.departure, value: shown)
    }
}

/// Tracks the pointer over the group's header; the tracking area costs nothing until it moves there.
private struct FolderPreviewAnchor: NSViewRepresentable {
    let browser: BrowserModel
    let groupID: UUID
    let enabled: Bool

    func makeNSView(context: Context) -> AnchorView { AnchorView() }

    func updateNSView(_ view: AnchorView, context: Context) {
        view.content = enabled ? (browser, groupID) : nil
        if !enabled { FolderPreviews.close(for: view) }
    }

    final class AnchorView: NSView {
        var content: (browser: BrowserModel, groupID: UUID)?

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            trackingAreas.forEach(removeTrackingArea)
            addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
        }

        override func mouseEntered(with event: NSEvent) { FolderPreviews.enter(self) }
        override func mouseExited(with event: NSEvent) { FolderPreviews.leave(self) }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil { FolderPreviews.close(for: self) }
            super.viewWillMove(toWindow: newWindow)
        }

        var screenFrame: NSRect? { window.map { $0.convertToScreen(convert(bounds, to: nil)) } }
    }
}

/// A panel that takes clicks without becoming key, so the page keeps the keyboard.
private final class PreviewPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The one folder preview on screen. It shows once the pointer has rested on a header, stays while the pointer goes
/// from the header to it, and ends a moment after the pointer leaves both, or at a click elsewhere, a key or a scroll.
/// A click on the header itself, a right click for its menu included, cancels it until the pointer leaves the header.
@MainActor
private enum FolderPreviews {
    private static let delay = Duration.milliseconds(600)
    /// Long enough to cross from the header to the preview.
    private static let grace = Duration.milliseconds(250)
    /// Long enough for the rows to close up (`BrowserDesign.motion`) before the panel shrinks to them.
    private static let settle = Duration.milliseconds(400)
    /// Long enough for the card to fade out (`FolderPreviewEntrance`) before the panel goes.
    private static let departure = Duration.milliseconds(150)

    private static weak var anchor: FolderPreviewAnchor.AnchorView?
    private static var pending: Task<Void, Never>?
    private static var monitor: Any?
    private static var overPanel = false
    private static var refitTask: Task<Void, Never>?
    private static var presence: FolderPreviewPresence?
    private static var hiding: Task<Void, Never>?
    /// Ends the preview as Aero stops being active; AppKit would show it again on return, wherever the pointer then is.
    private static var deactivation: Task<Void, Never>?
    /// The header clicked while under the pointer: no preview until the pointer leaves it.
    private static weak var dismissed: FolderPreviewAnchor.AnchorView?
    private static let panel: PreviewPanel = {
        let panel = PreviewPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The card draws its own shadow, which follows it as rows close up.
        panel.hasShadow = false
        panel.hidesOnDeactivate = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        return panel
    }()

    static func enter(_ view: FolderPreviewAnchor.AnchorView) {
        guard view.content != nil, dismissed !== view else { return }
        if anchor === view, panel.isVisible { pending?.cancel(); return }
        close()
        anchor = view
        pending = Task {
            do { try await Task.sleep(for: delay) } catch { return }
            show(for: view)
        }
        // From the moment the pointer rests: a click outside the preview, a key or a scroll ends it, shown or not yet.
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown, .scrollWheel]) { event in
            guard event.window !== panel else { return event }
            if event.type != .keyDown, event.type != .scrollWheel { dismissed = anchor }
            close()
            return event
        }
    }

    static func leave(_ view: FolderPreviewAnchor.AnchorView) {
        if dismissed === view { dismissed = nil }
        guard anchor === view else { return }
        closeSoon()
    }

    static func close(for view: FolderPreviewAnchor.AnchorView) {
        if anchor === view { close() }
    }

    private static func closeSoon() {
        pending?.cancel()
        pending = Task {
            do { try await Task.sleep(for: grace) } catch { return }
            if !overPanel { close() }
        }
    }

    private static func close() {
        pending?.cancel()
        pending = nil
        refitTask?.cancel()
        refitTask = nil
        anchor = nil
        overPanel = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        // The card fades out, then the panel goes.
        guard let presence else { return }
        presence.shown = false
        hiding?.cancel()
        hiding = Task {
            do { try await Task.sleep(for: departure) } catch { return }
            panel.orderOut(nil)
            panel.contentView = nil
            Self.presence = nil
        }
    }

    private static func show(for view: FolderPreviewAnchor.AnchorView) {
        guard anchor === view, NSApp.isActive, let (browser, groupID) = view.content, let window = view.window,
              let frame = view.screenFrame, let screen = window.screen?.visibleFrame else { return }
        let list = FolderPreviewList(browser: browser, groupID: groupID, close: { close() }, refit: { refit() })
            .onHover { hovering in
                overPanel = hovering
                if !hovering { closeSoon() } else { pending?.cancel() }
            }
        let presence = FolderPreviewPresence()
        let root = list
            .environment(\.layoutDirection, view.userInterfaceLayoutDirection == .rightToLeft ? .rightToLeft : .leftToRight)
            .modifier(FolderPreviewEntrance(presence: presence))
            // Its own window, outside the sidebar's environment.
            .browserMotionPreferences()
        let content = NSHostingView(rootView: root)
        content.appearance = window.effectiveAppearance
        let size = content.fittingSize
        // Placed by its card; the margin for the shadow lies around it.
        let margin = FolderPreviewList.margin
        let card = CGSize(width: size.width - 2 * margin, height: size.height - 2 * margin)
        let origin = FolderPreviewPlacement.origin(beside: frame, size: card, screen: screen,
                                                   rightToLeft: view.userInterfaceLayoutDirection == .rightToLeft)
        presence.headerOnLeft = origin.x > frame.minX
        hiding?.cancel()
        hiding = nil
        self.presence = presence
        panel.contentView = content
        if deactivation == nil {
            deactivation = Task {
                for await _ in NotificationCenter.default.notifications(named: NSApplication.didResignActiveNotification) { close() }
            }
        }
        panel.setFrame(NSRect(x: origin.x - margin, y: origin.y - margin, width: size.width, height: size.height), display: true)
        panel.orderFront(nil)
        // Once on screen, so the card comes from its first frame.
        Task { if self.presence === presence, anchor === view { presence.shown = true } }
    }

    /// Fits the panel to its rows, its top where it was: at once for rows arriving, after they have closed up for rows
    /// leaving.
    private static func refit() {
        refitTask?.cancel()
        guard let content = panel.contentView, content.fittingSize.height < panel.frame.height else { return fit() }
        refitTask = Task {
            do { try await Task.sleep(for: settle) } catch { return }
            fit()
        }
    }

    private static func fit() {
        guard panel.isVisible, let content = panel.contentView else { return }
        let size = content.fittingSize
        panel.setFrame(NSRect(x: panel.frame.minX, y: panel.frame.maxY - size.height, width: size.width, height: size.height), display: true)
    }

}
