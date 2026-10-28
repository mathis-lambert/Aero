import Foundation
import Testing
import WebKit
@testable import BrowserWebKit

// docs/MEDIA.md. Written as failure modes first:
// 1. A page's report is taken as it comes: unbounded text, artwork that is not a website address, unknown actions or
//    numbers that are not.
// 2. The artwork shown is the first listed, often the smallest, rather than the largest.
// 3. A report from a document since left, or a new document, keeps the old media.
// 4. The player's actions skip the site's own Media Session handlers, or do nothing without them.
// 5. Playing again resets when it began, so the player switches between two tabs that both play.
// 6. A muted video playing behind a page counts as begun, and takes the player and the system's Now Playing.
// 7. A player embedded in a frame of an article goes unseen, or the player's actions go to the article instead.

@Test func aMediaReportIsBounded() throws {
    let body: [String: Any] = [
        "playing": true, "hasElement": true,
        "session": [
            "title": String(repeating: "t", count: 5000), "artist": "  ", "album": 42,
            "artwork": [["src": "javascript:alert(1)", "sizes": "1024x1024"],
                        ["src": "https://cdn.example/96.png", "sizes": "96x96"],
                        ["src": "https://cdn.example/512.png", "sizes": "512x512"],
                        ["src": "https://cdn.example/128.png", "sizes": "128x128"]],
            "actions": ["nexttrack", "dance", 7],
            "position": ["duration": Double.infinity, "elapsed": 3]
        ] as [String: Any],
        "position": ["duration": 200, "elapsed": 250, "rate": 1]
    ]
    let report = try #require(MediaReport(body))
    #expect(report.title?.count == MediaScripts.maximumTextLength)
    #expect(report.artist == nil && report.album == nil, "Blank or not text: nothing")
    #expect(report.artwork == URL(string: "https://cdn.example/512.png"), "The largest website address")
    #expect(report.actions == [.nextTrack])
    #expect(report.position?.duration == 200 && report.position?.elapsed == 200, "The element's, its elapsed time within its duration")
    #expect(MediaReport(["playing": "yes"]) == nil)
}

@Test func playingOnKeepsWhenItBegan() throws {
    let report = try #require(MediaReport(["playing": true, "hasElement": true, "audible": true]))
    let began = Date(timeIntervalSince1970: 100)
    let first = try #require(report.media(isPlaying: true, previous: nil, now: began))
    #expect(first.startedAt == began)
    let later = report.media(isPlaying: true, previous: first, now: began.addingTimeInterval(30))
    #expect(later?.startedAt == began, "Still playing: it began when it began")
    let paused = report.media(isPlaying: false, previous: first, now: began.addingTimeInterval(60))
    #expect(paused?.startedAt == began && paused?.isPlaying == false)
    #expect(try #require(MediaReport(["playing": false, "hasElement": false])).media(isPlaying: false, previous: nil, now: began) == nil,
            "No element, no session, not playing: no media")
    let muted = try #require(MediaReport(["playing": true, "hasElement": true, "audible": false])).media(isPlaying: true, previous: nil, now: began)
    #expect(muted?.isPlaying == true && muted?.isAudible == false && muted?.startedAt == nil, "A muted video behind the page never begins")
    let named = try #require(MediaReport(["playing": true, "hasElement": true, "audible": false, "session": ["title": "Song"]]))
    #expect(named.media(isPlaying: true, previous: nil, now: began)?.startedAt == began, "Named by its site, it is meant to be heard")
}

/// A page whose Media Session names its track and handles the next one, and whose silent audio plays muted, as a page
/// may without a click. Needs access to macOS WebKit services.
@MainActor
@Test func aPageReportsWhatItPlaysAndTakesThePlayersActions() async throws {
    let page = BrowserPage(configuration: BrowserPage.configuration(store: .nonPersistent()))
    page.webView.loadHTMLString("""
        <title>Player</title>
        <script>
        navigator.mediaSession.metadata = new MediaMetadata({ title: "Song", artist: "Band",
            artwork: [{ src: "https://cdn.example/art.png", sizes: "300x300" }] });
        navigator.mediaSession.setActionHandler("nexttrack", () => { document.title = "Next"; });
        </script>
        """, baseURL: URL(string: "https://player.example/"))
    try await until { !page.webView.isLoading && page.webView.url != nil }
    try await until { page.activity.media?.title == "Song" }
    #expect(page.activity.media?.artist == "Band" && page.activity.media?.actions == [.nextTrack])
    #expect(page.activity.media?.artwork == URL(string: "https://cdn.example/art.png"))

    _ = try await page.webView.callAsyncJavaScript("""
        const rate = 8000, samples = rate * 4, data = new DataView(new ArrayBuffer(44 + samples * 2));
        const text = (offset, value) => [...value].forEach((c, i) => data.setUint8(offset + i, c.charCodeAt(0)));
        text(0, "RIFF"); data.setUint32(4, 36 + samples * 2, true); text(8, "WAVEfmt "); data.setUint32(16, 16, true);
        data.setUint16(20, 1, true); data.setUint16(22, 1, true); data.setUint32(24, rate, true); data.setUint32(28, rate * 2, true);
        data.setUint16(32, 2, true); data.setUint16(34, 16, true); text(36, "data"); data.setUint32(40, samples * 2, true);
        const audio = document.createElement("audio");
        audio.src = URL.createObjectURL(new Blob([data], { type: "audio/wav" }));
        audio.muted = true;
        document.body.append(audio);
        audio.play().catch(() => {});
        """, contentWorld: .page)
    try await until { page.activity.media?.isPlaying == true }
    #expect(page.activity.media?.startedAt != nil && page.activity.media?.title == "Song", "The session's name for the element's sound")

    page.perform(.nextTrack)
    try await until { page.webView.title == "Next" }
    page.perform(.pause)
    try await until { page.activity.media?.isPlaying == false }

    page.webView.loadHTMLString("<title>Quiet</title>", baseURL: URL(string: "https://quiet.example/"))
    try await until { page.webView.title == "Quiet" }
    #expect(page.activity.media == nil, "A new document starts with no media")
    page.dispose()
}

/// An article embedding a player from another origin, whose frame names its track and plays. Needs access to macOS
/// WebKit services and a loopback socket.
@MainActor
@Test func aPlayerInAFrameIsThePagesMedia() async throws {
    let frame = try HistoryPageServer(response: """
        HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n
        <script>
        navigator.mediaSession.metadata = new MediaMetadata({ title: "Embedded", artist: "Channel" });
        addEventListener("DOMContentLoaded", () => {
            const rate = 8000, samples = rate * 4, data = new DataView(new ArrayBuffer(44 + samples * 2));
            const text = (o, v) => [...v].forEach((c, i) => data.setUint8(o + i, c.charCodeAt(0)));
            text(0, "RIFF"); data.setUint32(4, 36 + samples * 2, true); text(8, "WAVEfmt "); data.setUint32(16, 16, true);
            data.setUint16(20, 1, true); data.setUint16(22, 1, true); data.setUint32(24, rate, true); data.setUint32(28, rate * 2, true);
            data.setUint16(32, 2, true); data.setUint16(34, 16, true); text(36, "data"); data.setUint32(40, samples * 2, true);
            const audio = document.createElement("audio");
            audio.src = URL.createObjectURL(new Blob([data], { type: "audio/wav" }));
            audio.muted = true;
            document.body.append(audio);
            audio.play().catch(() => {});
        });
        </script>
        """)
    let page = BrowserPage(configuration: BrowserPage.configuration(store: .nonPersistent()))
    page.webView.loadHTMLString("<title>Article</title><p>Text</p><iframe src='\(frame.url.absoluteString)'></iframe>",
                                baseURL: URL(string: "http://article.example/"))
    try await until { page.activity.media?.isPlaying == true }
    #expect(page.activity.media?.title == "Embedded" && page.activity.media?.artist == "Channel")
    page.perform(.pause)
    try await until { page.activity.media?.isPlaying == false }
    page.dispose()
}

@MainActor
private func until(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(10)
    while !condition() {
        guard ContinuousClock.now < deadline else { Issue.record("Timed out"); throw CancellationError() }
        try await Task.sleep(for: .milliseconds(20))
    }
}
