import AppKit
import BrowserCore
import Foundation
import WebKit

/// A two-finger swipe across the page toward its history (docs/BROWSING.md › Swiping through history). An arrow comes
/// in from the side the fingers move from and fills past `threshold`; let go there, the page goes back or forward.
/// Held there a moment, the arrow opens the pages that way: the fingers scroll them like a wheel, up bringing older
/// ones, lifting them goes to the page picked, and bringing them back toward the edge, or Escape, closes the list.
public struct PageSwipe: Equatable, Sendable {
    public enum Direction: Sendable { case back, forward }

    public enum Phase: Equatable, Sendable {
        /// Following the fingers, short of going.
        case tracking
        /// Past the threshold: letting go goes.
        case ready
        /// Held past the threshold: the pages that way, one picked; lifting the fingers goes there.
        case listing(picked: Int)
    }

    public let direction: Direction
    /// How far toward going, 1 at the threshold.
    public internal(set) var progress: Double
    public internal(set) var phase: Phase
    /// While listing, how far the fingers carry the list off its rest: `height` in picks toward the next one (up is
    /// positive), stretching less past either end; `width` in points, sideways since it opened. The list floats with it.
    public internal(set) var drift = CGSize.zero
}

/// A page of the tab's history, `offset` steps from the current one: negative back, positive forward.
public struct PageHistoryItem: Identifiable, Equatable, Sendable {
    public let offset: Int
    public let title: String
    public let url: URL
    public var id: Int { offset }
}

@MainActor
enum SwipeScripts {
    /// Function body: whether what is under `x`, `y`, or the page itself, can still scroll left or right, so the
    /// fingers scroll it rather than the history.
    static let scrollRoom = """
        let left = false, right = false;
        const room = (node, position, visible, total) => {
            if (total <= visible + 1) return;
            if (position > 0) left = true;
            if (position + visible < total - 1) right = true;
        };
        for (let node = document.elementFromPoint(x, y); node && node !== document.documentElement; node = node.parentElement) {
            const overflow = getComputedStyle(node).overflowX;
            if (overflow === "auto" || overflow === "scroll") room(node, Math.abs(node.scrollLeft), node.clientWidth, node.scrollWidth);
        }
        const root = document.scrollingElement;
        if (root) room(root, Math.abs(scrollX), innerWidth, root.scrollWidth);
        return { left, right };
        """
}

/// The fingers' swipe under way, before and after it shows.
struct SwipeTracking {
    /// Where the fingers went down, in the page's view.
    let point: CGPoint
    /// The fingers' travel since they went down, in points, right and down positive.
    var travel = CGSize.zero
    /// Decided once the fingers move clearly one way: horizontal or not.
    var horizontal: Bool?
    /// Whether what is under the fingers can scroll left or right, once the page answers.
    var room: (left: Bool, right: Bool)?
    /// The vertical travel since the list opened, past the last pick, which moves the pick.
    var listTravel: CGFloat = 0
    /// The sideways travel when the list opened.
    var listOrigin: CGFloat = 0
    /// Against an end of the list, already told by a tick.
    var atEnd = false
    var hold: Task<Void, Never>?
}

extension BrowserPage {
    /// The fingers' travel to the threshold.
    static let swipeThreshold: CGFloat = 130
    /// Held this long past the threshold, the arrow opens the list.
    static let swipeHold = Duration.milliseconds(450)
    /// The vertical travel that moves the pick by one page.
    static let swipeListStep: CGFloat = 24
    /// The list shows at most this many pages.
    static let swipeListLength = 10

    /// The pages back, most recent first, or forward, nearest first.
    public func history(_ direction: PageSwipe.Direction) -> [PageHistoryItem] {
        let list = webView.backForwardList
        let items = direction == .back ? Array(list.backList.reversed()) : list.forwardList
        return items.prefix(Self.swipeListLength).enumerated().map { index, item in
            PageHistoryItem(offset: direction == .back ? -(index + 1) : index + 1, title: item.title ?? "", url: item.url)
        }
    }

    /// Goes to a page of the list and closes it.
    func goToHistory(_ offset: Int) {
        swipe = nil
        guard let item = webView.backForwardList.item(at: offset) else { return }
        failure = nil
        webView.go(to: item)
    }

    /// Closes the list without going anywhere. Only a swipe showing is cleared: every scroll begins here, and a write
    /// would redraw the page's overlay each time.
    func dismissSwipe() {
        swipeTracking?.hold?.cancel()
        swipeTracking = nil
        if swipe != nil { swipe = nil }
    }

    /// Follows the fingers; answers whether the event is the swipe's alone, so the page under an open list never
    /// scrolls.
    @discardableResult
    func track(_ event: NSEvent) -> Bool {
        // Only a trackpad's fingers: a mouse wheel, or the momentum after the fingers left, never swipes.
        let listing = if case .listing? = swipe?.phase { true } else { false }
        guard event.hasPreciseScrollingDeltas else { return false }
        guard event.momentumPhase.isEmpty else { return listing }
        if event.phase.contains(.began) { beginSwipe(at: pageView.pagePoint(of: event)); return false }
        guard var tracking = swipeTracking else { return false }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) { endSwipe(cancelled: event.phase.contains(.cancelled)); return listing }
        guard event.phase.contains(.changed) else { return listing }
        // The fingers' own direction, whichever way content scrolls on this Mac.
        let sign: CGFloat = event.isDirectionInvertedFromDevice ? 1 : -1
        tracking.travel.width += event.scrollingDeltaX * sign
        tracking.travel.height += event.scrollingDeltaY * sign
        if case .listing(let picked)? = swipe?.phase, let direction = swipe?.direction {
            // Back toward the edge the arrow came from, the list closes and nothing happens.
            let toward = direction == .back ? tracking.travel.width : -tracking.travel.width
            if toward < Self.swipeThreshold / 2 { swipeTracking = nil; dismissSwipe(); return true }
            // The list follows the fingers as content does: up brings the pages further on under the arrow.
            tracking.listTravel -= event.scrollingDeltaY * sign
            let last = max(0, history(direction).count - 1)
            var next = picked
            while tracking.listTravel >= Self.swipeListStep / 2, next < last { next += 1; tracking.listTravel -= Self.swipeListStep }
            while tracking.listTravel <= -Self.swipeListStep / 2, next > 0 { next -= 1; tracking.listTravel += Self.swipeListStep }
            // Past an end the list stretches, less and less, and a tick says so once.
            let beyond = (next == last && tracking.listTravel > 0) || (next == 0 && tracking.listTravel < 0)
            if next != picked { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
            if beyond, abs(tracking.listTravel) > Self.swipeListStep / 2, !tracking.atEnd {
                NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                tracking.atEnd = true
            }
            if !beyond { tracking.atEnd = false }
            let along = tracking.listTravel / Self.swipeListStep
            swipe?.phase = .listing(picked: next)
            swipe?.drift = CGSize(width: tracking.travel.width - tracking.listOrigin,
                                  height: beyond ? (along < 0 ? -1 : 1) * pow(abs(along), 0.6) * 0.5 : along)
            swipeTracking = tracking
            return true
        }
        if tracking.horizontal == nil, max(abs(tracking.travel.width), abs(tracking.travel.height)) > 8 {
            tracking.horizontal = abs(tracking.travel.width) > abs(tracking.travel.height) * 1.5
            // Asked only of a horizontal swipe: a page scrolled up or down asks nothing.
            if tracking.horizontal == true { askScrollRoom(at: tracking.point) }
        }
        swipeTracking = tracking
        guard tracking.horizontal == true, let room = tracking.room else { return false }
        // Fingers moving right go back, as content follows them.
        let direction: PageSwipe.Direction = tracking.travel.width > 0 ? .back : .forward
        let possible = direction == .back ? webView.canGoBack && !room.left : webView.canGoForward && !room.right
        guard possible else { updateSwipe(nil); return false }
        let progress = min(abs(tracking.travel.width) / Self.swipeThreshold, 1.4)
        updateSwipe(PageSwipe(direction: direction, progress: progress, phase: progress >= 1 ? .ready : .tracking))
        return false
    }

    private func beginSwipe(at point: CGPoint) {
        // A list left open goes as the fingers come back.
        dismissSwipe()
        swipeTracking = SwipeTracking(point: point)
    }

    private func askScrollRoom(at point: CGPoint) {
        let generation = pageView.scrollGeneration
        let scale = webView.pageZoom * webView.magnification
        guard scale > 0 else { return }
        Task { [weak self] in
            guard let self else { return }
            let answer = try? await webView.callAsyncJavaScript(SwipeScripts.scrollRoom, arguments: ["x": point.x / scale, "y": point.y / scale],
                                                                contentWorld: PageScripts.world) as? [String: Any]
            // The page's answer is for these fingers only; no answer leaves the page nothing to scroll.
            guard pageView.scrollGeneration == generation, swipeTracking != nil else { return }
            swipeTracking?.room = (answer?["left"] as? Bool == true, answer?["right"] as? Bool == true)
        }
    }

    private func updateSwipe(_ next: PageSwipe?) {
        let wasReady = swipe?.phase == .ready
        if next != swipe { swipe = next }
        guard next?.phase == .ready, !wasReady else {
            if next?.phase != .ready { swipeTracking?.hold?.cancel() }
            return
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        // Held past the threshold, the arrow becomes the list of pages that way.
        swipeTracking?.hold = Task { [weak self] in
            do { try await Task.sleep(for: Self.swipeHold) } catch { return }
            guard let self, swipe?.phase == .ready, let direction = swipe?.direction, !history(direction).isEmpty else { return }
            swipe?.phase = .listing(picked: 0)
            swipeTracking?.listTravel = 0
            let origin = swipeTracking?.travel.width ?? 0
            swipeTracking?.listOrigin = origin
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
    }

    private func endSwipe(cancelled: Bool) {
        swipeTracking?.hold?.cancel()
        swipeTracking = nil
        guard let swipe else { return }
        switch swipe.phase {
        case .listing(let picked) where !cancelled:
            if let item = history(swipe.direction).dropFirst(picked).first { goToHistory(item.offset) } else { dismissSwipe() }
        case .ready where !cancelled:
            self.swipe = nil
            failure = nil
            if swipe.direction == .back { webView.goBack() } else { webView.goForward() }
        default:
            self.swipe = nil
        }
    }

    /// Escape closes the list the fingers hold, going nowhere; other keys are the page's.
    func handleSwipeKey(_ event: NSEvent) -> Bool {
        guard case .listing? = swipe?.phase, event.keyCode == 53 else { return false }
        swipeTracking = nil
        dismissSwipe()
        return true
    }
}
