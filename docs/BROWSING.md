# Browsing behaviors

Each section states the behavior, its owner, the ways it can fail, and how it is verified. The failure modes were written before the implementation.

## Favicons

Pages declare icons with `<link rel="icon">` and `apple-touch-icon`. After the main frame finishes loading, `BrowserPage` reads those declarations from an isolated content world and reports candidates, plus the origin's `/favicon.ico`. The app ranks them, downloads the best one, downsamples it to a small PNG, and caches it in memory and on disk per profile and host. Restored tabs show the cached icon without loading their page. The site initial or a globe symbol remains the fallback.

Failure modes:

1. A page returns arbitrary data from the icon query (non-string values, thousands of links, `javascript:` or `data:` URLs, very long strings).
2. The best candidate is not used: a 16 px icon wins over a 180 px touch icon, `sizes="any"` or unparsable sizes break ranking, relative URLs resolve against the wrong base.
3. A download is huge, slow, never ends, or is not an image; decoding a large image blocks the main thread or keeps full-size bitmaps in memory.
4. A late result writes an icon for a closed tab, or the icon of one site appears for another host.
5. Icons leak across profiles, or fetching sends the profile's cookies.
6. Every page load refetches the icon.
7. The disk cache is unbounded, or its files are named from unsanitized hosts.

Verification: E2E `testFaviconAppearsAndPersistsAcrossRelaunch` (fixture icon shown in the tab row, still shown after relaunch without loading the page). Isolated tests cover candidate ranking and parsing (2), which the E2E fixture cannot exercise exhaustively.

## First-frame reveal

A newly created or restored page stays transparent over the page surface until WebKit has rendered a frame of the new document, then fades in. This removes the white flash before dark pages paint. Detection uses public API: after the main frame commits, a double `requestAnimationFrame` in the isolated world resolves once a frame has been produced. A timeout reveals the page anyway. Later navigations in the same page do not hide it again.

Failure modes:

1. The page never becomes visible (script fails, page is blank, process crashes, navigation fails).
2. The reveal fires for the previous document or is re-armed on every navigation, making content blink.
3. The animation runs with Reduce Motion, or runs while idle.

Verification: E2E `testNewPageRevealsItsContent` samples the rendered page color after load. Error and crash paths reveal immediately by construction.

## Popups

`window.open` and `target="_blank"` links get a real `WKWebView` created from WebKit's configuration, so `window.opener`, `postMessage` and OAuth flows work. The popup becomes a tab in the opener's space and is selected. `window.close()` from a popup closes its tab and returns to the opener. A page in a popup relationship does not hibernate while the other page is loaded.

Failure modes:

1. Returning a web view built from another configuration (different data store or process), which breaks opener access or crosses profiles.
2. Adding the browser's user scripts twice to the inherited configuration.
3. A popup opened after its opener closed, or after its space changed, creates an orphan tab or returns a stale web view.
4. `window.close()` from an ordinary page closes a tab the user opened.
5. Hibernation unloads an opener or popup during an OAuth flow.
6. A popup without a web URL (`about:blank`) produces an invalid tab record and blocks session saves.

Verification: E2E `testPopupTalksToOpenerAndClosesItself` (the popup messages its opener, then closes; the opener tab is selected again).

## Keyboard routing between the browser and pages

Web applications use shortcuts such as ⌘K. The command catalog marks each command as **reserved** (always handled by the browser, like Safari's ⌘T, ⌘W, ⌘L) or **page-first** (offered to a focused page first; the browser acts only if the page does not handle it).

Failure modes:

1. A page captures a reserved shortcut and traps the user (⌘W or ⌘T do nothing).
2. The browser steals a page-first shortcut the page handles.
3. The browser never receives a page-first shortcut the page ignores.
4. Text entry, IME composition, or accented input is intercepted.
5. Behavior differs between the menu, the shortcut and the command palette.

Verification: E2E `testPageShortcutsDoNotOverrideReservedCommands` and `testPageHandlesPageFirstShortcuts` with a fixture page that calls `preventDefault()` on every Command key.

## Selected tab highlight

The selection background is one shared shape that slides between rows with the shell spring. With Reduce Motion it moves without animation. Nothing animates while idle.

Verification: screenshots attached to the E2E run; selection state is asserted through accessibility traits.

## Known limits

- SVG icons are skipped (ImageIO cannot decode them); plain-HTTP icons are blocked by App Transport Security except on `localhost` and local network hosts.
- Popups open as tabs, not as separate sized windows; `windowFeatures` are ignored.
- Only the main frame is checked for its first rendered frame.
- The selection slide is verified visually through screenshots, not by an assertion on the animation.

## Running the E2E suite

`Scripts/run-e2e.sh [test-identifier…]` runs the UI tests into `/tmp/auro-e2e-<run-id>.xcresult` and writes a `manifest.txt` next to it with the command, revision, working-tree status, Xcode and macOS versions. Fixtures are served by an in-process HTTP server in the test runner (`FixtureServer`) on `localhost`, from `Tests/AuroUITests/Fixtures`.
