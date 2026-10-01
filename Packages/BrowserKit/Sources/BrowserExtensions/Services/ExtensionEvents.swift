import Foundation
import WebKit

/// Bounded event queues for extension contexts, including suspended backgrounds.
@MainActor
final class ExtensionEvents {
    struct Event: Sendable {
        let name: String
        /// The listener's arguments, as a JSON array.
        let arguments: Data

        init?(name: String, arguments: [Any]) {
            guard let data = try? JSONSerialization.data(withJSONObject: arguments) else { return nil }
            self.name = name
            self.arguments = data
        }

        var reply: [String: Any] { ["name": name, "arguments": (try? JSONSerialization.jsonObject(with: arguments)) ?? [Any]()] }
    }

    nonisolated static let wait = Duration.seconds(25)
    /// A context that stopped asking for longer than this is gone.
    nonisolated static let abandoned = Duration.seconds(60)
    nonisolated static let maximumQueued = 64
    /// A context asks again at once after each answer; one that has not for this long is not running.
    nonisolated static let between = Duration.seconds(5)

    /// A context waiting for events, known by its view.
    @MainActor
    final class Listener {
        weak var view: WKWebView?
        let isBackground: Bool
        var names: Set<String>
        var queue: [Event] = []
        var waiting: (id: UUID, continuation: CheckedContinuation<[Event], Never>)?
        var lastSeen = ContinuousClock.now

        init(view: WKWebView, isBackground: Bool, names: Set<String>) {
            self.view = view
            self.isBackground = isBackground
            self.names = names
        }

        var isGone: Bool { view == nil || (waiting == nil && ContinuousClock.now - lastSeen > ExtensionEvents.abandoned) }
        var isRunning: Bool { view != nil && (waiting != nil || ContinuousClock.now - lastSeen < ExtensionEvents.between) }

        func take() -> [Event] {
            let events = queue
            queue = []
            return events
        }

        func resume(waitID: UUID? = nil) {
            guard let waiting, waitID == nil || waiting.id == waitID else { return }
            self.waiting = nil
            lastSeen = .now
            waiting.continuation.resume(returning: take())
        }
    }

    private var listeners: [String: [ObjectIdentifier: Listener]] = [:]
    /// What each extension's background listened for, kept while it is not running.
    private var backgroundNames: [String: Set<String>] = [:]
    /// Events for a background that is starting.
    private var backgroundQueue: [String: [Event]] = [:]

    /// Registers what the context listens for; its events wait for it from now on. `waits` answers the context's
    /// previous wait, which a new wait replaces; a registration sent along with another request leaves it waiting.
    @discardableResult
    func listen(for extensionID: String, from view: WKWebView, isBackground: Bool, names: Set<String>, waits: Bool = true) -> Listener {
        prune(extensionID)
        let key = ObjectIdentifier(view)
        let listener = listeners[extensionID]?[key] ?? Listener(view: view, isBackground: isBackground, names: names)
        listener.names = names
        listener.lastSeen = .now
        if waits { listener.resume() }
        listeners[extensionID, default: [:]][key] = listener
        if isBackground {
            backgroundNames[extensionID] = names
            listener.queue += backgroundQueue.removeValue(forKey: extensionID) ?? []
        }
        return listener
    }

    /// The context's next events: those queued, or the first to come within `wait`, or none.
    func next(for listener: Listener) async -> [Event] {
        guard listener.queue.isEmpty else { return listener.take() }
        let waitID = UUID()
        let timeout = Task { [weak listener] in
            do { try await Task.sleep(for: Self.wait) } catch { return }
            listener?.resume(waitID: waitID)
        }
        defer { timeout.cancel() }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { listener.waiting = (waitID, $0) }
        } onCancel: {
            Task { @MainActor [weak listener] in listener?.resume(waitID: waitID) }
        }
    }

    /// Queues the event for every context of the extension that listens for it. Returns `true` when only a background
    /// that is not running listens, which the caller then starts.
    func deliver(_ event: Event, to extensionID: String) -> Bool {
        prune(extensionID)
        var backgroundHeard = false
        for listener in listeners[extensionID]?.values ?? [:].values where listener.names.contains(event.name) {
            // A suspended background gets its events when it starts again, whichever view it then has.
            if listener.isBackground && !listener.isRunning { continue }
            listener.queue = Array((listener.queue + [event]).suffix(Self.maximumQueued))
            listener.resume()
            if listener.isBackground { backgroundHeard = true }
        }
        guard !backgroundHeard, backgroundNames[extensionID]?.contains(event.name) == true else { return false }
        backgroundQueue[extensionID] = Array(((backgroundQueue[extensionID] ?? []) + [event]).suffix(Self.maximumQueued))
        return true
    }

    /// The event names some context of the extension listens for.
    func names(for extensionID: String) -> Set<String> {
        prune(extensionID)
        return (listeners[extensionID]?.values ?? [:].values).reduce(backgroundNames[extensionID] ?? []) { $0.union($1.names) }
    }

    func drop(_ extensionID: String) {
        for listener in listeners.removeValue(forKey: extensionID)?.values ?? [:].values { listener.resume() }
        backgroundNames[extensionID] = nil
        backgroundQueue[extensionID] = nil
    }

    private func prune(_ extensionID: String) {
        listeners[extensionID] = listeners[extensionID]?.filter { !$0.value.isGone }
    }
}

extension ProfileExtensions {
    static let idleEvent = "idle.onStateChanged"

    /// Waits for the next events the calling context listens for.
    func nextEvents(_ names: Set<String>, for context: WKWebExtensionContext, from caller: WKWebView) async -> [[String: Any]] {
        await events.next(for: listen(names, for: context, from: caller, waits: true)).map(\.reply)
    }

    /// What the context listens for, as it says with each request: an event that follows a request it made, such
    /// as `permissions.onAdded`, finds its listeners even before its next wait arrives.
    @discardableResult
    func listen(_ names: Set<String>, for context: WKWebExtensionContext, from caller: WKWebView, waits: Bool) -> ExtensionEvents.Listener {
        let extensionID = context.uniqueIdentifier
        if names.contains("tts.onVoicesChanged"), providedGrants[extensionID]?.contains("tts") == true { _ = speechService() }
        let wasListeningForIdle = events.names(for: extensionID).contains(Self.idleEvent)
        let listener = events.listen(for: extensionID, from: caller, isBackground: isBackground(caller, of: context), names: names, waits: waits)
        if events.names(for: extensionID).contains(Self.idleEvent) != wasListeningForIdle { startListeningForIdle(extensionID) }
        return listener
    }

    /// Its service worker's view has no path; a background page's is the one the manifest names.
    private func isBackground(_ view: WKWebView, of context: WKWebExtensionContext) -> Bool {
        let path = view.url?.path ?? ""
        let page = (context.webExtension.manifest["background"] as? [String: Any])?["page"] as? String
        return path.isEmpty || path == "/" || path == "/_generated_background_page.html" || page.map { path == "/" + $0 } == true
    }

    /// Queues the event for the extension's listeners, starting its background when only that listens.
    func deliver(_ name: String, _ arguments: [Any], to extensionID: String) {
        guard let context = contexts[extensionID], let event = ExtensionEvents.Event(name: name, arguments: arguments) else { return }
        if events.deliver(event, to: extensionID) {
            context.loadBackgroundContent { error in
                if error != nil { Self.logger.error("An extension's background could not start for an event") }
            }
        }
    }
}
