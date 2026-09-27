# Performance

## Display cadence and responsiveness

SwiftUI/AppKit schedule the shell's native springs and scrolling against the display. Aero adds no
timer or display link to force continuous redraws. The New Tab entrance uses SwiftUI's display-paced
timeline; the slow decorative drift is limited to 30 FPS and rests after 20 seconds without activity.
Both stop with Reduce Motion, an inactive window or Low Power Mode, including a power-mode change
while the page is visible.

Each window supplies `browserReduceMotion` from the native Reduce Motion setting and Low Power
Mode notifications. Shell transitions, hover feedback, zoom, profile paging, shakes, the control-bar
glow and download effects use that shared policy. No polling or separate animation scheduler is
needed. This does not override website `prefers-reduced-motion`, which remains a system accessibility
preference rather than a battery-mode signal.

WebKit's JavaScript/DOM rendering cadence is distinct from native/compositor scrolling. At page
creation, `PageRendering` disables the private `PreferPageRenderingUpdatesNear60FPSEnabled` feature.
The feature is discovered once through `WKPreferences._features`; the setter `_setEnabled:forFeature:`
uses optional, typed Objective-C dispatch. Missing features/selectors leave WebKit's default intact.
This is an explicitly accepted private API exception: recheck it on macOS/WebKit upgrades and replace
it with a public API when available. It does not replace scrolling, force an FPS, change the user's
display settings, or disable WebKit's background, power or thermal throttling. Higher web frame rates
can increase energy use. See [WebKit's API request](https://bugs.webkit.org/show_bug.cgi?id=294338) and
the [SPI declaration](https://github.com/WebKit/WebKit/blob/main/Source/WebKit/UIProcess/API/Cocoa/WKPreferencesPrivate.h).

Sidebar tabs are grouped in one pass, retaining their session order. Progress notifications update only progress; they do not republish page metadata.
The control bar publishes local history independently of network suggestions, with cancellation
for both when the query changes.

`RenderingE2ETests/testPageFrameCadenceAndSmoothScroll` records a bounded local page's median and
p95 `requestAnimationFrame` interval, display capabilities, window geometry and power state. It also
checks that smooth scrolling actually moved the page. Its attachment is a callback-cadence measure,
not a physical display/compositor FPS measurement. It has no hard 120 FPS assertion: an external
60 Hz screen, Low Power Mode, instrumentation and scheduling can all reduce the observed cadence.
Measure on the intended display; use Instruments Animation Hitches to assess native frame delivery.
Place Aero on that display with the native Window menu before the run. The cadence test retains its
numeric report rather than cropping a window screenshot: XCUITest's window capture can fail on a
secondary display even when the page is responsive. Screen capability is not a substitute for the
recorded intervals.
`ControlBarE2ETests/testHistoryDoesNotWaitForSlowSuggestions` delays suggestions by 2.5 seconds and
checks that local history appears first and a cancelled query cannot restore stale results.

Run the cadence test with `Scripts/run-e2e.sh AeroUITests/RenderingE2ETests`. For a Release measure,
use the documented `xcodebuild` command below with `-only-testing:AeroUITests/RenderingE2ETests`
and a unique `-resultBundlePath`. Run launch metrics separately from functional tests: Xcode can
complete a mixed suite without collecting launch metrics, so inspect the metrics rather than
treating a passing test as a timing result.

## Tab hibernation

A tab is a durable record; its `WKWebView` is a live resource owned by `WebPageRegistry`. Hibernation releases the web view and its WebContent process while keeping the tab, its history and scroll position (`interactionState`, kept in memory). Activating the tab restores that state; after a relaunch, tabs reload from their URL.

`HibernationPolicy` (BrowserCore) decides, from pure inputs, which live pages are due:

| Rule | Behavior |
| --- | --- |
| Active page | Never hibernated |
| Idle limit | Background pages unused for the chosen delay (15 min – 4 h, default 30 min) |
| Memory budget | Beyond one live background page per 2 GB of RAM (2–24), least recently used pages go first |
| Memory pressure | Warning: idle limit capped at 5 min. Critical: every eligible background page |
| Favorites | Eligible unless "Keep favorites awake" is on |
| Disabled | Nothing is hibernated |

Before unloading, `BrowserPage.hibernationBlocker()` keeps a page awake when it captures the camera or microphone, is in full screen or picture in picture, plays media, or holds text the user typed and did not submit. A page with an active download, or in a popup relationship with a loaded page, also stays awake. Typed fields are tracked by a script in an isolated content world, so pages cannot read or alter that state. If input cannot be inspected, the page stays awake. Exempt pages are checked again after 5 min and do not count against the budget.

Scheduling uses one owned task that sleeps until the next deadline, with a 1 min tolerance so the system can coalesce wakeups. It never polls. Activation, settings, favorite changes and memory pressure events reschedule it.

Limits: only the main frame is inspected for unsent text.

## Session writes

`SessionStore.scheduleSave` coalesces a burst of changes into at most one atomic write per second, always with the latest snapshot. Termination calls `save` directly, which supersedes any pending write. A title change alone schedules no write: it is saved with the next change or at termination, so a page that animates its title (a timer, an unread count) never rewrites the session. History coalesces titles the same way (`docs/HISTORY.md`).

## Measuring

Report the build configuration, hardware, and scenario (idle, navigation, many tabs, media) with any number.

- **Signposts:** subsystem `app.getaero.browser`; categories `Launch`, `PageLifecycle`, `Storage`. Record with Instruments' os_signpost or Points of Interest instruments to see launch-to-session-ready, session load/write, and page creation, restoration and hibernation.
- **Cold launch:** `LaunchPerformanceTests` measures launch until the window is responsive. Use the Release configuration:
  ```sh
  xcodebuild -project Aero.xcodeproj -scheme Aero -configuration Release \
    -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/aero-derived \
    -only-testing:AeroUITests/LaunchPerformanceTests test
  ```
- **Memory:** `swift Scripts/measure-memory.swift` reports the footprint of the running app plus the WebKit processes attributed to it. Add `--sample 1` to sample over time and `--detailed` for per-category memory. WebKit processes of other apps, such as Safari, are excluded.
