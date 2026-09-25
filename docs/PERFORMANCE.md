# Performance

## Tab hibernation

A tab is a durable record; its `WKWebView` is a live resource owned by `WebPageRegistry`. Hibernation releases the web view and its WebContent process while keeping the tab, its history and scroll position (`interactionState`, kept in memory). Activating the tab restores that state; after a relaunch, tabs reload from their URL.

`HibernationPolicy` (BrowserCore) decides, from pure inputs, which live pages are due:

| Rule | Behavior |
| --- | --- |
| Active page | Never hibernated |
| Idle limit | Background pages unused for the chosen delay (15 min – 4 h, default 30 min) |
| Memory budget | Beyond one live background page per 2 GB of RAM (2–24), least recently used pages go first |
| Memory pressure | Warning: idle limit capped at 5 min. Critical: every eligible background page |
| Pinned tabs | Eligible unless "Keep pinned tabs awake" is on |
| Disabled | Nothing is hibernated |

Before unloading, `BrowserPage.hibernationBlocker()` keeps a page awake when it captures the camera or microphone, is in full screen, plays media, or holds text the user typed and did not submit. Typed fields are tracked by a script in an isolated content world, so pages cannot read or alter that state. If input cannot be inspected, the page stays awake. Exempt pages are checked again after 5 min and do not count against the budget.

Scheduling uses one owned task that sleeps until the next deadline, with a 1 min tolerance so the system can coalesce wakeups. It never polls. Activation, settings, pin changes and memory pressure events reschedule it.

Known limits: only the main frame is inspected for unsent text; downloads and popups opened by another tab are not implemented yet, so they are not exemptions; `interactionState` is not persisted across launches.

## Session writes

`SessionStore.scheduleSave` coalesces a burst of changes into at most one atomic write per second, always with the latest snapshot. Termination calls `save` directly, which supersedes any pending write.

## Measuring

Report the build configuration, hardware, and scenario (idle, navigation, many tabs, media) with any number.

- **Signposts:** subsystem `dev.auro`; categories `Launch`, `PageLifecycle`, `Storage`. Record with Instruments' os_signpost or Points of Interest instruments to see launch-to-session-ready, session load/write, and page creation, restoration and hibernation.
- **Cold launch:** `LaunchPerformanceTests` measures launch until the window is responsive. Use the Release configuration:
  ```sh
  xcodebuild -project Auro.xcodeproj -scheme Auro -configuration Release \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/auro-derived \
    -only-testing:AuroUITests/LaunchPerformanceTests test
  ```
- **Memory:** `swift Scripts/measure-memory.swift` reports the footprint of the running app plus the WebKit processes attributed to it. Add `--sample 1` to sample over time and `--detailed` for per-category memory. WebKit processes of other apps, such as Safari, are excluded.
