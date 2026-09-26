# Browsing

Failure modes were written before each implementation. E2E tests run against local fixtures (`Tests/AeroUITests/Fixtures`) served by `FixtureServer` on `localhost`.

## Favicons

After the main frame loads, `BrowserPage` reads the page's icon links in an isolated content world. The app ranks them with the origin's `/favicon.ico`, downloads the best through an anonymous session, downsamples it to a small PNG and caches it on disk per profile and host. Memory keeps the 256 most recently shown icons, each observed on its own. Restored tabs show the cached icon without loading.

Failure modes:

1. The icon query returns hostile data (non-strings, thousands of links, `javascript:` or `data:` URLs, huge strings).
2. Ranking picks a worse icon (`sizes="any"`, unparsable sizes, wrong base URL).
3. A download is huge, endless or not an image; decoding blocks the main thread or keeps full-size bitmaps.
4. A late result writes an icon for a closed tab or another host.
5. Icons cross profiles, or requests carry the profile's cookies.
6. Every load refetches the icon.
7. Cache files are named from unsanitized hosts.
8. Other links placed first crowd icons out of the bounded query.

Verification: E2E `testFaviconAppearsAndPersistsAcrossRelaunch` (icon declared after 33 feed links; 8). Isolated `FaviconCandidateTests` cover 1–2 and `FaviconStoreTests` 5 and 7.

## First-frame reveal

A new or restored page stays transparent over the page surface until WebKit has rendered a frame of the committed document (a double `requestAnimationFrame` in the isolated world), then fades in, so dark pages never flash white. A timeout and every failure path reveal it anyway.

Failure modes: the page never appears; it blinks on later navigations; the fade runs with Reduce Motion.

Verification: E2E `testNewPageRevealsItsContent` samples the rendered color.

## Popups

`window.open` and `target="_blank"` get a `WKWebView` from WebKit's own configuration, so `window.opener`, `postMessage` and OAuth work. The popup becomes a selected tab in the opener's space; `window.close()` closes it and returns to the opener.

Failure modes:

1. A web view from another configuration breaks opener access or crosses profiles.
2. User scripts are added twice.
3. A popup opened after its opener closed creates an orphan tab.
4. `window.close()` closes a tab the user opened.
5. Hibernation unloads either side during an OAuth flow.
6. A popup at `about:blank` produces an invalid tab record.

Verification: E2E `testPopupTalksToOpenerAndClosesItself`.

## Keyboard routing

Each catalog command is **reserved** (the browser always acts, like ⌘T, ⌘W, ⌘L) or **page-first** (a focused page may handle it; the browser acts otherwise).

Failure modes: a page traps a reserved shortcut; the browser steals a page-first shortcut the page handled, or never gets one the page ignored; text entry or IME composition is intercepted; the menu, the shortcut and the control bar behave differently.

Verification: E2E `testPageShortcutsDoNotOverrideReservedCommands` and `testPageHandlesPageFirstShortcuts`, with a fixture that calls `preventDefault()` on every Command key.

## Find in page

⌘F opens a floating bar prefilled with the selection or the previous search. It searches as you type (case-insensitive, wrapping); Return and ⌘G go forward, ⇧Return and ⇧⌘G back. Escape returns focus to the page; switching tabs closes the bar. The shortcuts are page-first, so web editors keep their own find.

Failure modes: a search per keystroke, or results for an older query; the bar searches another tab; focus is lost after dismissal; a miss is shown by color alone.

Verification: E2E `testFindInPageSelectsMatchesAndReportsMisses`.

## Downloads

Undisplayable responses, `download` links and `Content-Disposition: attachment` become downloads, saved to Downloads (a test folder under `AERO_TEST_DATA`) with a sanitized, unique name, quarantined and tagged with their source. The footer's downloads button lists them for the session in a popover (`docs/PROFILES.md`); the Dock shows the active count. Closing or hibernating the tab never stops one.

Failure modes:

1. A suggested name escapes the folder, hides itself, is empty or too long.
2. An existing file is overwritten.
3. Progress redraws the sidebar for every packet.
4. A failure cannot be retried, or a cancel keeps its partial file.
5. Tests write into the user's Downloads folder.
6. Hibernation or closing interrupts a download.

Verification: E2E `testDownloadCompletesAndCanBeCleared`. Isolated `DownloadFilenameTests` cover 1–2.

## Reordering and pinning

Tabs drag within the list, onto the pinned grid to pin and back to unpin, with an insertion line. Dragged to another app, a tab exports its address.

Failure modes: a drop lands in the wrong place or loses the tab; a tab changes space; text or files from other apps are taken for a tab.

Verification: E2E `testTabsReorderAndPinByDragging`.

## Quitting

⌘Q and the Quit menu item ask first, in a prompt over the browser window: Return quits, Escape cancels, and a second ⌘Q quits too. "Quit, and don't ask again" turns the prompt off; Settings › General turns it back on. Quitting from the Dock, at logout or at restart never asks. Quitting saves the session first.

Failure modes:

1. The prompt blocks a logout, a restart or a quit from the Dock.
2. Return or Escape reaches the focused page or field instead of the prompt.
3. The prompt opens while the browser window is minimized or closed, so nothing can answer it.
4. "Don't ask again" is lost after relaunch, or cannot be undone.
5. The session is not saved when quitting from the prompt.

Verification: E2E `testQuitAsksFirst` (Escape keeps the app running; Return quits and the session survives; "don't ask again" quits at once on the next ⌘Q and shows in Settings; 2, 4, 5). 1 holds by construction: only the menu item asks.

## Site data and permissions

Right-clicking the reload button offers Clear cookies, Clear cache and Site settings…; all three are catalog commands, so the command palette has them too. They act on the selected page's site in its profile's data store. WebKit groups data by site (the registrable domain), so clearing `mail.example.com` clears `example.com` and its other subdomains, as Safari does. Clearing cookies or all data reloads the page, so it stops using what was removed.

Site settings is a popover on the reload button: the site's cookie count and whether it stores other data, Delete data, and a decision for camera, microphone and location: Ask (WebKit's own prompt, every time), Allow or Block. Decisions belong to the profile, are saved with the session and keyed by the page's origin (`scheme://host[:port]`, lowercased, without the default port). An embedded frame gets the page's decision; WebKit's permissions policy already keeps cross-origin frames out unless the page delegates to them. Reset permissions returns every decision to Ask.

The app declares camera, microphone and location usage, with the hardened runtime entitlements that let macOS ask for them.

Failure modes:

1. Clearing touches another site, or another profile's store.
2. A subdomain keeps the site's cookies, such as a session cookie set on the parent domain.
3. The page keeps using removed cookies until the user reloads it.
4. A decision is keyed on another origin (an embedded frame, a different port or letter case), so it does not apply to the page it was set on.
5. A decision is lost at relaunch, or survives its profile's deletion.
6. A camera and microphone request is granted while one of the two is blocked, or Ask grants without a prompt.
7. WebKit waits forever for a decision, or a closed tab answers one.
8. macOS refuses the device although the site is allowed (missing usage description or entitlement).
9. The actions run on a browser page (`aero://`) or with no page.

Verification: E2E `testSiteDataClearsAndPermissionsPersist` (Clear cookies and Delete data empty the site's cookies and reload it while `127.0.0.1` keeps its own; blocked camera and location are refused without a prompt; decisions survive a relaunch; 1, 3, 5). By construction: 2 (WebKit removes whole site records), 4 (`SiteOrigin` is the only key, from the page's address), 5's deletion case (decisions live on the profile), 6 and 7 (`BrowserPage`'s delegate), 9 (the commands are disabled without a web page). 8 needs a real device prompt and is checked by hand; Clear cache has no observable E2E effect.

## Limits

- SVG icons are skipped (ImageIO cannot decode them); plain-HTTP icons are blocked by App Transport Security outside local hosts.
- Popups open as tabs, not sized windows.
- Find reports whether a match exists, not how many.
- Downloads are kept for the session only.
- History skips intermediate redirects; selecting a restored tab counts as a visit.
