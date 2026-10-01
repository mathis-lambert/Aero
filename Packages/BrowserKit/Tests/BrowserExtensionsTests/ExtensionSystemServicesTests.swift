import Foundation
import IOKit.pwr_mgt
import Testing
@testable import BrowserExtensions

// Failure modes: replacing a power request leaves both assertions active; invalid input
// discards an existing request; releasing or unloading leaks a system assertion.
@MainActor
@Test func powerRequestsReplaceAndReleaseTheirSystemAssertions() throws {
    let power = ExtensionPower(), id = UUID().uuidString
    defer { power.close(id) }
    func assertions() throws -> [[String: Any]] {
        var byProcess: Unmanaged<CFDictionary>?
        #expect(IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess)
        let processes = try #require(byProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]])
        return (processes[NSNumber(value: ProcessInfo.processInfo.processIdentifier)] ?? [])
            .filter { $0[kIOPMAssertionNameKey] as? String == "Aero extension \(id)" }
    }
    try power.request("system", for: id)
    #expect(try assertions().count == 1)
    #expect(throws: (any Error).self) { try power.request("invalid", for: id) }
    #expect(try assertions().count == 1)
    try power.request("display", for: id)
    #expect(try assertions().count == 1)
    #expect(try assertions().first?[kIOPMAssertionTypeKey] as? String == kIOPMAssertionTypePreventUserIdleDisplaySleep)
    power.release(id)
    #expect(try assertions().isEmpty)
}

// Failure modes: bad ranges/types enter the speech engine, an unavailable voice is silently
// substituted, or unloading one extension cancels another extension's queued speech.
@MainActor
@Test func speechRejectsInvalidOptionsAndKeepsOtherExtensionsQueued() throws {
    for options: [String: Any] in [["rate": 0], ["rate": 11], ["pitch": -1], ["volume": 2], ["rate": true],
                                   ["enqueue": "yes"], ["requiredEventTypes": ["unavailable"]], ["voiceName": "No such fixture voice"]] {
        #expect(throws: (any Error).self) {
            try ExtensionSpeech.Request(["text": "Example", "requestID": "invalid", "options": options], extensionID: "a")
        }
    }
    let speech = ExtensionSpeech()
    defer { speech.stop() }
    var final: [String: String] = [:]
    speech.onEvent = { _, id, event in
        if let type = event["type"] as? String, ["interrupted", "cancelled"].contains(type) { final[id] = type }
    }
    func request(_ id: String, owner: String, enqueue: Bool) throws -> ExtensionSpeech.Request {
        try .init(["text": String(repeating: "Example text. ", count: 100), "requestID": id,
                   "options": ["enqueue": enqueue, "volume": 0]], extensionID: owner)
    }
    try speech.speak(request("current-a", owner: "a", enqueue: false))
    try speech.speak(request("queued-b", owner: "b", enqueue: true))
    try speech.speak(request("queued-a", owner: "a", enqueue: true))
    speech.close("a")
    #expect(final == ["current-a": "interrupted", "queued-a": "cancelled"])
    #expect(speech.isSpeaking)
    speech.stop()
    #expect(final["queued-b"] == "interrupted")
    #expect(!speech.isSpeaking)
}

@Test func speechCallbacksAreDeliveredWithoutSerializingFunctions() async throws {
    let harness = try CompatibilityHarness(manifest: #"{"permissions":["tts"]}"#, prelude: """
        let answerSpeech;
        const eventAnswer = new Promise(resolve => answerSpeech = resolve);
        const originalFetch = fetch;
        globalThis.fetch = async (url, init) => {
            if (url.split('?')[0].endsWith('/events/next')) return {ok:true,json:async () => ({value:await eventAnswer})};
            const reply = await originalFetch(url, init);
            if (url.split('?')[0].endsWith('/tts/speak')) {
                const body = JSON.parse(init.body);
                answerSpeech([{name:'tts.onEvent',arguments:[body.requestID,{type:'end',charIndex:7}]}]);
            }
            return reply;
        };
        """)
    harness.run("chrome.tts.speak('Example',{onEvent:event=>globalThis.spokenEvent=event},()=>globalThis.spokenCallback=true)")
    let deadline = ContinuousClock.now + .seconds(2)
    while !harness.bool("globalThis.spokenCallback && globalThis.spokenEvent"), ContinuousClock.now < deadline { await Task.yield() }
    #expect(harness.string("JSON.stringify(spokenEvent)") == #"{"type":"end","charIndex":7}"#)
    #expect(harness.bool("requests.some(request=>request.route==='tts/speak' && request.body.text==='Example' && !('onEvent' in request.body.options))"))
}
