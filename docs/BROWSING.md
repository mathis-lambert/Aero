# Browsing

The site in the selected tab (control center, site data, permissions, ad blocking, picture in picture) is in `docs/SITE_CONTROLS.md`. E2E tests run against local fixtures (`Tests/AeroUITests/Fixtures`) served by `FixtureServer` on `localhost`.

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

Undisplayable responses, `download` links and `Content-Disposition: attachment` become downloads, saved to Downloads (a test folder under `AERO_TEST_DATA`) with a sanitized, unique name, quarantined and tagged with their source. The Dock shows the active count. Closing or hibernating the tab never stops one.

They live in a popover from the sidebar footer's downloads button. The button shows the progress of active downloads as a ring; the popover lists the session's downloads with progress, cancel, retry, Show in Finder and Clear, or says there are none.

When a download starts, its file icon is thrown from the pointer (or the page's center when the pointer is elsewhere) in an arc into the downloads button, shrinking on the way, in about 0.6 s, and the button takes the hit: a small kick, then a damped wobble on its base. Nothing flies with Reduce Motion or while the sidebar is hidden; the flight never takes clicks.

Failure modes:

1. A suggested name escapes the folder, hides itself, is empty or too long.
2. An existing file is overwritten.
3. Progress, the ring or the list redraws the sidebar for every packet.
4. A failure cannot be retried, or a cancel keeps its partial file.
5. Tests write into the user's Downloads folder.
6. Hibernation or closing interrupts a download.
7. Clearing removes an active download.
8. The popover shows a stale list, or cannot be reopened after it closes.
9. A retry, a clear, a relaunch or a progress update throws a file again.
10. The file flies to the wrong place after the window is resized, or while the sidebar is hidden.
11. The flight runs with Reduce Motion, blocks clicks, or stays on screen.

Verification: E2E `testDownloadCompletesAndCanBeCleared` opens the popover, waits for the download and clears it once finished (8). Isolated `DownloadFilenameTests` cover 1–2. By construction: 3 (the ring updates in whole percents, `BrowserDownload.progressStep`), 7 (Clear removes only downloads that stopped, `clearInactive`), 9 (the flight is triggered only by `DownloadCoordinator.lastStarted`, which a new download sets). 10 and 11 are checked by hand.

## Favorites and open tabs

A profile's sidebar has three ordered areas: a favorites grid, pinned favorite rows (optionally grouped), then a separator, New Tab and ordinary open tabs.

- **Favorites** stay when closed: ⌘W, the close button or Close unloads the page and keeps the favorite in its place; clicking it loads its address again. A favorite shows as a tile in the grid (its favicon, three per row), or as a row under the grid, loose or in a group. A group opens and closes from its header, and remembers it; Ungroup keeps its favorites, as loose rows.
- **Favorite lifecycle**: an opened favorite row shows a minus; closing releases its page but retains its record. A closed row shows a remove cross on hover. Removing an open favorite from its menu makes it an ordinary tab; removing a closed favorite deletes it. Open/closed favorite state is runtime-only and independent of WebKit hibernation. Favorites start closed after relaunch. Placement and ordering remain in the versioned session JSON, with one `TabPlace` per record; no parallel favorites table or duplicated URL record.
- **New Tab** is one permanent selectable row. Selecting it or pressing ⌘T highlights that row; entering an address creates an ordinary tab below it. There is no duplicate New Tab row or close control.
- **Open tabs** close for good; Reopen Closed Tab brings them back.
- **Dragging** moves a tab or a favorite anywhere in its profile's page: into the grid, where the tiles part where it will land, between rows, into a group (onto its header, or between its rows when it is open) or among the open tabs. The gap follows the pointer; releasing lands the tab in it. Only during a drag, an empty grid reveals a profile-colored dashed target with a plus. It animates in on pickup and out on drop or cancellation, respecting Reduce Motion. An idle or populated grid has no extra target. The two native preview images are cached while the drag is over the sidebar. Haptic feedback marks pickup, a changed insertion position and drop. SwiftUI owns pickup and cancellation. A profile-local AppKit drop target changes the preview and commits the chosen position synchronously; it does not intercept ordinary clicks. Dragged to another app, a tab exports its address. Tabs from another profile, text and files are refused.
- **Context menu**: Add to Favorites or Remove from Favorites, Duplicate (an open tab with the same address, after it), New Group with Tab, Move to Group, Move to Profile (a new tab in that profile, loaded with its website data; a favorite stays a favorite, outside any group), Rename… (in place; an empty name gives back the page's title) and Close. A group's menu has Rename… and Ungroup.

Failure modes:

1. A closed favorite disappears, or its page keeps running.
2. A drop lands somewhere other than the gap shown, or the gap jumps back and forth under a still pointer because the tiles moved under it.
3. A drag that ends outside the sidebar or in another app leaves a gap, a hidden tab or a changed order.
4. A tab changes profile through a drag, a tab from another profile's page is taken, or text and files are taken for a tab.
5. A tab points to a group that does not exist (removed, in another space, or a tampered session), or ungrouping loses favorites.
6. A tab moved to another profile keeps its live page, and so the first profile's cookies, or a late event of that page updates it.
7. A blank name is saved, the page's later titles replace the given name, or Escape saves the edit.
8. Closing a selected favorite leaves a closed page on screen; a duplicate or a move selects the wrong tab.
9. Favorites, groups, names and their order are lost on relaunch.
10. Animated transitions ignore Reduce Motion, or decorative animations continue while idle.
11. An empty drop target remains visible while idle, or disappears before the chosen destination is committed.

Verification: E2E `testTabsMoveByDraggingAndFavoritesStayWhenClosed` (reordering, the grid from both sides, a closed favorite, back to the open tabs; 1–2, 8), `testGroupsRenameAndDuplicateSurviveRelaunch` (a group from the menu, Move to Group, collapsing, Rename, Escape, Duplicate, relaunch, Ungroup; 5, 7–9) and `ProfilesE2ETests.testTabMovesToAnotherProfile` (6). Isolated `BrowserSessionTests` cover the session rules the UI cannot reach (4–5): moves across spaces and into foreign groups are refused, and a saved tab in an unknown group fails validation. Cancellation outside the sidebar is covered by `testTabsMoveByDraggingAndFavoritesStayWhenClosed`. Layout and selection transitions use `browserAnimation`; Reduce Motion and physical haptic feedback still require manual verification.

Favorites interaction verification also includes `EssentialsE2ETests.testEmptyGridAndPinnedRowCloseThenRemove` for the empty grid, grid-to-list drop, minus/close/reopen/remove and deletion after relaunch. The permanent New Tab row is covered by `testNewTabIsOnePermanentSelectableRow`. Expanded French labels are exercised by `testFavoritesWithExpandedFrenchLabels`. Physical trackpad haptics and actual RTL rendering still require a manual check on supported hardware.

## Quitting

⌘Q and the Quit menu item ask first, in a prompt over the browser window: Return quits, Escape cancels, and a second ⌘Q quits too. "Quit, and don't ask again" turns the prompt off; Settings › General turns it back on. Quitting from the Dock, at logout or at restart never asks. Quitting saves the session first.

Failure modes:

1. The prompt blocks a logout, a restart or a quit from the Dock.
2. Return or Escape reaches the focused page or field instead of the prompt.
3. The prompt opens while the browser window is minimized or closed, so nothing can answer it.
4. "Don't ask again" is lost after relaunch, or cannot be undone.
5. The session is not saved when quitting from the prompt.

Verification: E2E `testQuitAsksFirst` (Escape keeps the app running; Return quits and the session survives; "don't ask again" quits at once on the next ⌘Q and shows in Settings; 2, 4, 5). 1 holds by construction: only the menu item asks.

## Limits

- SVG icons are skipped (ImageIO cannot decode them); plain-HTTP icons are blocked by App Transport Security outside local hosts.
- Popups open as tabs, not sized windows.
- Find reports whether a match exists, not how many.
- Downloads are kept for the session only.
