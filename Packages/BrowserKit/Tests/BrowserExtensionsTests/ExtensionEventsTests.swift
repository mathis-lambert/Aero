import Foundation
import Testing
import WebKit
@testable import BrowserExtensions

// Events Aero delivers to extension contexts. Failure modes: an event lost while a context is between two waits, one
// delivered to a context that does not listen for it, a suspended background never woken or its events dropped, and
// a waiting context left hanging after unloading or cancellation, and an obsolete timeout answering a later wait.

private let extensionID = String(repeating: "a", count: 32)

@MainActor
private func event(_ name: String, _ arguments: [Any] = []) throws -> ExtensionEvents.Event {
    try #require(ExtensionEvents.Event(name: name, arguments: arguments))
}

@MainActor
@Test func anEventWaitsForTheNextRequestOfEachListeningContext() async throws {
    let events = ExtensionEvents()
    let popup = WKWebView(), page = WKWebView()
    let popupListener = events.listen(for: extensionID, from: popup, isBackground: false, names: ["idle.onStateChanged"])
    let pageListener = events.listen(for: extensionID, from: page, isBackground: false, names: ["downloads.onChanged"])
    #expect(events.deliver(try event("idle.onStateChanged", ["idle"]), to: extensionID) == false, "A running context needs no waking")
    let delivered = await events.next(for: popupListener)
    #expect(delivered.map(\.name) == ["idle.onStateChanged"])
    #expect(String(decoding: delivered[0].arguments, as: UTF8.self) == #"["idle"]"#)
    #expect(pageListener.queue.isEmpty, "A context that does not listen gets nothing")
}

@MainActor
@Test func aWaitingContextIsAnsweredAsTheEventComes() async throws {
    let events = ExtensionEvents()
    let view = WKWebView()
    let listener = events.listen(for: extensionID, from: view, isBackground: false, names: ["notifications.onClicked"])
    async let delivered = events.next(for: listener)
    try await Task.sleep(for: .milliseconds(50))
    _ = events.deliver(try event("notifications.onClicked", ["n1"]), to: extensionID)
    #expect(await delivered.map(\.name) == ["notifications.onClicked"])
}

@MainActor
@Test func aSuspendedBackgroundIsWokenAndGetsItsEventsWhateverViewItHasThen() async throws {
    let events = ExtensionEvents()
    let suspended = WKWebView(), restartedView = WKWebView()
    let first = events.listen(for: extensionID, from: suspended, isBackground: true, names: ["idle.onStateChanged"])
    // It answered and was then suspended: not waiting, and not asking again for longer than a context between waits.
    first.lastSeen = .now - ExtensionEvents.between - .seconds(1)
    #expect(events.deliver(try event("idle.onStateChanged", ["locked"]), to: extensionID), "Only its background listens, so it is started")
    let restarted = events.listen(for: extensionID, from: restartedView, isBackground: true, names: ["idle.onStateChanged"])
    #expect(await events.next(for: restarted).map(\.name) == ["idle.onStateChanged"])
}

@MainActor
@Test func anEventNobodyListensForIsDropped() throws {
    let events = ExtensionEvents()
    #expect(events.deliver(try event("idle.onStateChanged"), to: extensionID) == false)
    #expect(events.names(for: extensionID).isEmpty)
}

@MainActor
@Test func unloadingAnswersWaitingContexts() async throws {
    let events = ExtensionEvents()
    let view = WKWebView()
    let listener = events.listen(for: extensionID, from: view, isBackground: false, names: ["idle.onStateChanged"])
    async let delivered = events.next(for: listener)
    try await Task.sleep(for: .milliseconds(50))
    events.drop(extensionID)
    #expect(await delivered.isEmpty)
    #expect(events.names(for: extensionID).isEmpty)
}

@MainActor
@Test func cancellingARequestEndsOnlyItsOwnWait() async throws {
    let events = ExtensionEvents()
    let view = WKWebView()
    let listener = events.listen(for: extensionID, from: view, isBackground: false, names: ["idle.onStateChanged"])
    let cancelled = Task { await events.next(for: listener) }
    while listener.waiting == nil { await Task.yield() }
    let oldWait = try #require(listener.waiting?.id)
    cancelled.cancel()
    #expect(await cancelled.value.isEmpty)

    let next = Task { await events.next(for: listener) }
    while listener.waiting == nil { await Task.yield() }
    // A timeout or cancellation queued by the earlier request reaches the listener after it asks again.
    listener.resume(waitID: oldWait)
    #expect(listener.waiting != nil, "An obsolete callback must leave the new request waiting")
    _ = events.deliver(try event("idle.onStateChanged", ["active"]), to: extensionID)
    #expect(await next.value.map(\.name) == ["idle.onStateChanged"])
}

@MainActor
@Test func queuesAreBounded() throws {
    let events = ExtensionEvents()
    let view = WKWebView()
    let listener = events.listen(for: extensionID, from: view, isBackground: false, names: ["downloads.onChanged"])
    for index in 0..<(ExtensionEvents.maximumQueued + 10) { _ = events.deliver(try event("downloads.onChanged", [index]), to: extensionID) }
    #expect(listener.queue.count == ExtensionEvents.maximumQueued)
    let newest = try #require(listener.queue.last)
    #expect(String(decoding: newest.arguments, as: UTF8.self) == "[\(ExtensionEvents.maximumQueued + 9)]", "The newest are kept")
}
