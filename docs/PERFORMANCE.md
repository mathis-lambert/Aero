# Performance

## Display cadence and responsiveness

SwiftUI/AppKit schedule the shell's native springs and scrolling against the display. Aero adds no
timer or display link to force continuous redraws. The New Tab entrance uses SwiftUI's display-paced
timeline; the slow decorative drift is limited to 30 FPS and rests after 20 seconds without activity.
Both stop with Reduce Motion, an inactive window or Low Power Mode, including a power-mode change
while the page is visible.

Each window supplies `browserReduceMotion` from the native Reduce Motion setting and Low Power
Mode notifications. Shell transitions, hover feedback, zoom, space paging, shakes, the control-bar
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

`RenderingPerformanceTests/testPageFrameCadenceAndSmoothScroll` records a bounded local page's median and
p95 `requestAnimationFrame` interval, display capabilities, window geometry and power state. It also
checks that smooth scrolling actually moved the page. Its attachment is a callback-cadence measure,
not a physical display/compositor FPS measurement. It has no hard 120 FPS assertion: an external
60 Hz screen, Low Power Mode, instrumentation and scheduling can all reduce the observed cadence.
Measure on the intended display; use Instruments Animation Hitches to assess native frame delivery.
Place Aero on that display with the native Window menu before the run. The cadence test retains its
numeric report rather than cropping a window screenshot: XCUITest's window capture can fail on a
secondary display even when the page is responsive. Screen capability is not a substitute for the
recorded intervals.
`BrowsingJourneys/testSuggestionsFollowTheEngineAndStayPrivate` delays suggestions by 2.5 seconds and
checks that local history appears first and a cancelled query cannot restore stale results.

Every measurement runs in the Performance plan, in Release: `Scripts/test.sh performance`, or one of them with
`Scripts/test.sh performance AeroUITests/RenderingPerformanceTests`. Functional plans never include them: Xcode can
complete a mixed suite without collecting launch metrics, so inspect the metrics rather than treating a passing
test as a timing result.

## Onboarding

`Scripts/test.sh performance AeroUITests/OnboardingPerformanceTests` measures application CPU during
five seconds of idle onboarding, after an interaction and its 20-second rest delay. It runs once in Release
and retains the metric and a screenshot; it does not measure physical frame presentation or total GPU energy.

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

## Measuring

Report the build configuration, hardware, and scenario (idle, navigation, many tabs, media) with any number.

- **Signposts:** subsystem `app.getaero.browser`; categories `Launch`, `PageLifecycle`, `Storage`. Record with Instruments' os_signpost or Points of Interest instruments to see launch-to-session-ready, session load/write, and page creation, restoration and hibernation.
- **Cold launch:** `LaunchPerformanceTests` measures launch until the window is responsive:
  `Scripts/test.sh performance AeroUITests/LaunchPerformanceTests`.
- **Memory:** `swift Scripts/measure-memory.swift` reports the footprint of Aero Dev by default (pass `Aero` to inspect stable), plus the WebKit processes attributed to it. Add `--sample 1` to sample over time and `--detailed` for per-category memory. WebKit processes of other apps, such as Safari, are excluded.

## Spaces

Only the current sidebar and its two neighbors are constructed. Equatable sidebar content is independent of the gesture offset; model observation still invalidates changed records. Gestures only update a translation until committing selection. No neighbor preloads WebKit. The one global hibernation owner and RAM-derived page budget cover every space/profile; active media, captures, unsaved input and downloads remain exempt, so this is not a hard cap on total memory. Unused profiles do not instantiate extension controllers at startup.

Opaque WebKit interaction data is retained only when represented as Data, within a global 32-entry/16-MiB budget. Evicted or unsupported interaction state falls back to the saved URL. Arbitrary web-app state is not promised to survive hibernation. Same-profile tab moves keep their live page and identity. Cross-profile transitions discard interaction state.

`SpacesPerformanceTests/testManySpacesKeepLazyPagesAndStableSwitching` seeds 4 profiles,
13 spaces and 240 tab records through `BrowserStore` before launch. It checks lazy startup, loads local
pages across spaces, records application CPU/memory metrics during repeated switching, then
checks a playing video survives a background-space round trip. Run it explicitly in Release:

```sh
Scripts/test.sh performance AeroUITests/SpacesPerformanceTests
```

The test emits `AERO_SPACES_STAGE` markers with eight-second observation windows for an external
sampler to include the app's WebKit processes. XCTest's CPU/memory metrics cover Aero itself;
menu-driven wall-clock durations include accessibility automation and do not measure swipe frame
pacing. Keep the `.xcresult`, reproduction manifest and working-tree patch written by the runner.
