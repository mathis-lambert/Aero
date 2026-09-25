# Control bar

The failure modes below were written before the implementation.

## Behavior

One component, `ControlBarView` (`App/Features/ControlBar`), is the browser's only address, search and command field. It appears in two places with the same behavior:

- **New Tab page:** a little above the middle of the page, focused on ⌘T. Results open in this tab.
- **Over a tab:** its top edge at 28% of the window's height. ⌘L opens it with the tab's address selected, and its results replace the tab's page. ⌘K opens it empty, and results open in a new tab. On the New Tab page, both shortcuts focus the page's own bar instead.

Results, in order, recomputed as the text changes:

1. **Go:** the address the text resolves to, or a search for the text with the chosen engine. Always first, so Return with no selection keeps its meaning. Text that is not a web address (`javascript:`, `file:`) is searched, never opened.
2. **Suggestions** from the chosen engine, up to four, when suggestions are on.
3. **Open tabs** of the current space whose title or address matches, up to three. Choosing one switches to it.
4. **History** of the current profile matching the text, up to three, skipping pages already open.
5. **Commands** of the central catalog whose title matches, with their keyboard shortcut. With no text, the bar over a tab lists every available command, so it doubles as the shortcut reference; the New Tab page shows no list until you type.

Arrows move the selection, as does the pointer once it moves (a bar opening under a still pointer keeps its first row), Return opens it, a click opens a row, and Escape closes the bar over a tab or clears the New Tab field. Commands run through the same dispatcher as menus and shortcuts.

## Search engines

Settings › General chooses the engine (DuckDuckGo by default, Google, Bing, Brave Search) and whether to show its suggestions (on by default). The engine builds both the search address and the suggestion request; both use the engines' public OpenSearch endpoints.

Suggestion requests go through an ephemeral session without cookies, cache or credentials, so they never carry a profile's identity. Text that looks like an address (it contains a dot or a scheme, or names localhost) is never sent. Requests wait for a pause in typing, and a newer text cancels an older request.

## New Tab page

Each time the page appears, at launch or for a new tab, a gust rises from below its bottom edge. It travels fast (2,000 points per second), so little separates the wind from the bar, but what it does to each point unfolds in its own time. A soft, undithered light in the profile's accent rises with it from the bottom of the page and throws itself on the control bar, shrinking as it closes in, then fades as the bar lights up. As the gust passes the crescent, the dots grow in with a slight pop (0.75 s), swell a little, and the air gently pushes the texture away and lets it settle in one slow swing (about 0.7 s). When the light reaches the bar, a band of light crosses it from bottom to top, quick to start and unhurried to finish (0.9 s), and the bar barely stirs; then a fine ring and a faint halo remain. The gust, the light and the bar share one clock.

The wind is the design system's mistral field drawn as "trame" dots in the profile's accent: on the dark canvas the dots take the accent's luminous version and the densest glow toward white; on the light canvas the sparse dots are paler and the densest carry the full tint. The crescent is thickest at its crest and tapers toward the ends, which dissolve before the page's sides; dots never touch, so the texture stays fine. A Metal shader (`Wind.metal`) draws every dot on the GPU, antialiased, and skips the pixels no gust can reach; the app only advances the time. The field drifts briskly along the wind, its gusts reshaping as they travel, and the crescent's line sways and breathes while someone is there, at 30 frames per second. It rests 20 seconds after the page appears or the pointer last moved over it, and resumes from the same shapes on the next movement. It never drifts while the window is inactive, with Reduce Motion (the page then appears whole, without the gust) or in Low Power Mode, so a New Tab page left open costs nothing.

Measured on the Release build (Apple silicon, window in front, the pointer still): drifting uses about 0.57 s of CPU per 10 s in the app process; resting and background use none (0.00–0.01 s per 20 s). The compiled shader adds 12 KB to the bundle. Building needs Xcode's Metal Toolchain component (`xcodebuild -downloadComponent MetalToolchain`); it is a build tool only.

## Failure modes

1. Suggestions for an older text arrive late and replace the results of the current text.
2. Suggestions are requested while they are turned off, for text that looks like an address, or with a profile's cookies.
3. A suggestion endpoint returns malformed, huge or hostile data (non-strings, thousands of entries, very long strings, the query itself, duplicates).
4. A slow or unreachable engine delays typing, blocks the main actor or leaves the list waiting.
5. The selection points past the end of the list after it shrinks, or Return opens something other than the highlighted row.
6. The chosen engine is not used for searches typed in the bar, or the choice is lost after relaunch.
7. ⌘L opens a new tab instead of replacing the current page, ⌘K replaces it, or either opens a second bar over the New Tab page.
8. Choosing an open tab opens a duplicate instead of switching; history from another profile appears.
9. A command runs differently from its menu item, or its shortcut shown in the bar differs from the menu.
10. The wind or the intro keeps animating while nobody is there, while the window is inactive, with Reduce Motion or in Low Power Mode; the intro repeats without a new tab; resuming jumps to other shapes.
11. Escape leaves the bar open, or closing it leaves keyboard focus nowhere.

Verification: E2E `ControlBarE2ETests` covers 1–2 and 4–11 against the fixture server, which serves the suggestion and search endpoints and records the requests it receives (`AERO_TEST_SEARCH` points the engines there in test runs only). Isolated `SearchEngineTests` cover 3 and the address rules of 2, which the fixtures cannot vary exhaustively. The wind (10) is checked from the attached screenshots and by measuring the app's CPU time while drifting, resting and in the background, as above.
